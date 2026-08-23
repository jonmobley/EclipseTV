//
//  CloudKitSyncEngine.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import os.log
import UIKit

/// CloudKit `CKSyncEngine` backend for private-database Show + capture sync.
@MainActor
final class CloudKitSyncEngine: NSObject, SyncBackend {

    let container: CKContainer
    let account: CloudKitAccountMonitor
    var engine: CKSyncEngine?
    private lazy var downloader = CloudKitAssetDownloader(container: container)
    let shareRoots = CloudKitShareRootStore()
    private lazy var shareCoordinator: CloudKitShareCoordinator = {
        let coordinator = CloudKitShareCoordinator(
            container: container,
            database: container.privateCloudDatabase
        )
        coordinator.onShareRootEstablished = { [weak self] id in
            self?.noteShareRootEstablished(id)
        }
        coordinator.onShareRootRemoved = { [weak self] id in
            self?.noteShareRootRemoved(id)
        }
        return coordinator
    }()
    private lazy var sharedEngineHost = CloudKitSharedSyncHost(container: container)

    private let stateKey = "EclipseTV.cloudKit.syncEngineState"
    private let showModifiedKey = "EclipseTV.cloudKit.showModified."
    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "CloudKitSync")
    private var didStart = false
    private var storeObservers: [NSObjectProtocol] = []
    /// When true, local store notifications do not schedule uploads (remote apply).
    var isApplyingRemote = false

    /// Pending record IDs that hit quotaExceeded and need re-queue after space frees.
    var quotaHeldRecordIDs: [CKRecord.ID] = []

    init(container: CKContainer = CKContainer(identifier: CloudKitSchema.containerIdentifier)) {
        self.container = container
        self.account = CloudKitAccountMonitor(container: container)
        super.init()
    }

    // MARK: - SyncBackend

    var isAccountAvailable: Bool { account.isAccountAvailable }

    var pauseReason: SyncPauseReason? { account.pauseReason }

    func start() {
        guard !didStart else { return }
        didStart = true
        account.start()
        observeLocalStores()
        Task { await bootstrapEngineIfPossible() }
        NotificationCenter.default.addObserver(
            forName: CloudKitAccountMonitor.didChangeNotification,
            object: account,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.bootstrapEngineIfPossible()
                self?.retryQuotaHeldIfNeeded()
            }
        }
    }

    func scheduleShowSave(id: UUID) {
        rememberShowModified(id: id)
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.showRecordID(for: id))
        ])
    }

    func scheduleShowDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.showRecordID(for: id))
        ])
    }

    func scheduleCaptureSave(id: String) {
        guard let engine else { return }
        CaptureStore.shared.setSyncState(id: id, .pendingUpload)
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.mediaRecordID(for: id))
        ])
    }

    func scheduleCaptureDelete(id: String) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.mediaRecordID(for: id))
        ])
    }

    func schedulePDFSave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.pdfRecordID(for: id))
        ])
    }

    func schedulePDFDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.pdfRecordID(for: id))
        ])
    }

    func downloadAsset(
        id: String,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        guard isAccountAvailable else {
            completion(.failure(SyncLocalError.noAccount))
            return
        }
        downloader.download(id: id, progress: progress, completion: completion)
    }

    func removeLocalDownload(id: String) {
        CaptureStore.shared.removeLocalDownload(id: id)
    }

    func presentShareUI(forShowId id: UUID, from presenter: AnyObject) {
        guard let vc = presenter as? UIViewController else { return }
        guard isAccountAvailable else {
            let alert = UIAlertController(
                title: "iCloud Required",
                message: SyncPauseReason.noAccount.userMessage,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            vc.present(alert, animated: true)
            return
        }
        shareCoordinator.presentShareUI(forShowId: id, from: vc)
    }

    // MARK: - Bootstrap

    private func bootstrapEngineIfPossible() async {
        await account.refresh()
        guard account.isAccountAvailable else {
            engine = nil
            return
        }
        guard engine == nil else { return }

        var serialization: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: stateKey) {
            serialization = try? JSONDecoder().decode(
                CKSyncEngine.State.Serialization.self,
                from: data
            )
        }

        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        let syncEngine = CKSyncEngine(configuration)
        engine = syncEngine
        syncEngine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: CloudKitSchema.zoneID))
        ])
        enqueueAllLocal()
        sharedEngineHost.start()
        logger.info("CKSyncEngine started")
    }

    /// Pushes every local Show and pending capture/PDF once after engine start.
    ///
    /// Does **not** stamp Show `modifiedAt` — inventing “now” on bootstrap/foreground
    /// would let an idle device win LWW over real offline edits on another phone.
    func enqueueAllLocal() {
        guard let engine else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for album in LocalAlbumStore.shared.albums {
            changes.append(.saveRecord(CloudKitSchema.showRecordID(for: album.id)))
        }
        // Mirror PDF filtering: `.localOnly` captures must never upload on bootstrap.
        for id in CaptureStore.shared.idsNeedingUpload {
            changes.append(.saveRecord(CloudKitSchema.mediaRecordID(for: id)))
        }
        // Only PDFs the server hasn't acknowledged — a blanket re-enqueue would
        // re-upload every document's bytes on each launch.
        for id in PDFStore.shared.idsNeedingUpload {
            changes.append(.saveRecord(CloudKitSchema.pdfRecordID(for: id)))
        }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    /// Recreates the private library zone and re-enqueues local content.
    ///
    /// Used when the zone is deleted server-side or a save fails with `zoneNotFound`.
    /// Never deletes local data in response to that signal.
    func recoverFromZoneLoss() {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: CloudKitSchema.zoneID))
        ])
        enqueueAllLocal()
    }

    /// Re-enqueues pending uploads after foregrounding (or a transient failure).
    func retryPendingWork() {
        guard engine != nil, account.isAccountAvailable else { return }
        retryQuotaHeldIfNeeded()
        enqueueAllLocal()
    }

    private func observeLocalStores() {
        let center = NotificationCenter.default
        storeObservers.append(center.addObserver(
            forName: LocalAlbumStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.reconcileShowsWithEngine(notification) }
        })
    }

    /// Schedules saves for the Show that changed, or every Show when unspecified.
    private func reconcileShowsWithEngine(_ notification: Notification) {
        // Shared-DB apply only sets the controller flag — check both so accepted
        // Shares don't fork into the private zone.
        guard engine != nil,
              !isApplyingRemote,
              !EclipseSyncController.shared.isApplyingRemote else { return }
        if let id = notification.userInfo?[LocalAlbumStore.changedAlbumIdKey] as? UUID {
            scheduleShowSave(id: id)
            return
        }
        for album in LocalAlbumStore.shared.albums {
            scheduleShowSave(id: album.id)
        }
    }

    func persistEngineState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    func bootstrapEngineIfPossiblePublic() async {
        await bootstrapEngineIfPossible()
    }

    /// Records a Show LWW clock. Local edits pass `Date()`; remote apply passes the
    /// winning merged timestamp (never invent a newer stamp on bootstrap).
    func rememberShowModified(id: UUID, at date: Date = Date()) {
        UserDefaults.standard.set(
            date.timeIntervalSince1970,
            forKey: showModifiedKey + id.uuidString
        )
    }

    func showModified(id: UUID) -> Date {
        let raw = UserDefaults.standard.double(forKey: showModifiedKey + id.uuidString)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : Date.distantPast
    }

    private func retryQuotaHeldIfNeeded() {
        guard account.pauseReason != .quotaExceeded,
              account.isAccountAvailable,
              let engine,
              !quotaHeldRecordIDs.isEmpty else { return }
        let held = quotaHeldRecordIDs
        quotaHeldRecordIDs = []
        engine.state.add(pendingRecordZoneChanges: held.map { .saveRecord($0) })
        account.clearQuotaPause()
    }

    func holdForQuota(_ recordID: CKRecord.ID) {
        if !quotaHeldRecordIDs.contains(recordID) {
            quotaHeldRecordIDs.append(recordID)
        }
        account.noteQuotaExceeded()
    }
}

// MARK: - Errors

enum SyncLocalError: LocalizedError {
    case noAccount

    var errorDescription: String? {
        SyncPauseReason.noAccount.userMessage
    }
}
