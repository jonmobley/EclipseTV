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
    let shareRoots = CloudKitShareRootStore()
    /// Deletes that must outlive a nil engine (signed out / pre-bootstrap).
    let pendingDeletes = CloudKitPendingDeleteStore()
    /// Shows with unsent local edits, so foregrounding doesn't re-push the lot.
    let showDirty = CloudKitShowDirtyStore()
    /// MediaItems with unsent preference edits, for the same reason.
    let mediaDirty = CloudKitMediaDirtyStore()
    /// MediaItems whose local copy the user removed, so arriving bytes aren't kept.
    let evictedMedia = CloudKitEvictedMediaStore()
    /// Zones of records owned by other users, learned from the shared database.
    let sharedZones = CloudKitSharedZoneIndex()
    private lazy var downloader = CloudKitAssetDownloader(
        container: container,
        sharedZones: sharedZones
    )
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
    lazy var sharedEngineHost = CloudKitSharedSyncHost(
        container: container,
        sharedZones: sharedZones
    )

    let stateKey = "EclipseTV.cloudKit.syncEngineState"
    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "CloudKitSync")
    private var didStart = false
    var storeObservers: [NSObjectProtocol] = []
    /// When true, local store notifications do not schedule uploads (remote apply).
    var isApplyingRemote = false

    /// Pending record IDs that hit quotaExceeded and need re-queue after space frees.
    var quotaHeldRecordIDs: [CKRecord.ID] = []

    /// Server (or last saved) `CKRecord` system fields, so saves keep a change tag.
    ///
    /// Building a fresh `CKRecord` for an id that already exists is an insert, and
    /// CloudKit rejects it with "record to insert already exists". This is persisted
    /// because an in-memory cache makes the *first* save of every record after a cold
    /// launch exactly that rejected insert.
    let lastKnownRecords = CloudKitRecordSystemFieldsStore()

    /// - Parameter container: Obtain it from `CloudKitAvailability.container()`.
    ///   There is deliberately no default: building one inline traps in an
    ///   unentitled build, and a default argument hides that from the caller.
    init(container: CKContainer) {
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
        showDirty.markDirty(id)
        scheduleSave(CloudKitSchema.showRecordID(for: id))
    }

    func scheduleShowDelete(id: UUID) {
        showDirty.markClean(id)
        scheduleDelete(CloudKitSchema.showRecordID(for: id))
    }

    func scheduleCaptureSave(id: String) {
        CaptureStore.shared.setSyncState(id: id, .pendingUpload)
        scheduleSave(CloudKitSchema.mediaRecordID(for: id))
    }

    func scheduleCaptureDelete(id: String) {
        scheduleDelete(CloudKitSchema.mediaRecordID(for: id))
    }

    func schedulePDFSave(id: UUID) {
        scheduleSave(CloudKitSchema.pdfRecordID(for: id))
    }

    func schedulePDFDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.pdfRecordID(for: id))
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
        // Asking for the file again withdraws any earlier "remove download", so
        // future fetches are free to keep the bytes they arrive with.
        if let recordName = mediaRecordName(forAnyId: id) {
            evictedMedia.clear(recordName)
        }
        downloader.download(id: id, progress: progress, completion: completion)
    }

    func removeLocalDownload(id: String) {
        // Remembered so a later edit to this item on any device does not quietly
        // restore the download from the asset that rides along with the record.
        if let recordName = mediaRecordName(forAnyId: id) {
            evictedMedia.note(recordName)
        }
        if CaptureStore.shared.record(id: id) != nil {
            CaptureStore.shared.removeLocalDownload(id: id)
            return
        }
        ImportedMediaStore.shared.removeLocalDownload(id: id)
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

    // MARK: - Show LWW clock

    /// Records a Show LWW clock. Local edits pass `Date()`; remote apply passes the
    /// winning merged timestamp (never invent a newer stamp on bootstrap).
    func rememberShowModified(id: UUID, at date: Date = Date()) {
        UserDefaults.standard.set(
            date.timeIntervalSince1970,
            forKey: CloudKitSchema.showModifiedKey(for: id)
        )
    }

    func showModified(id: UUID) -> Date {
        let raw = UserDefaults.standard.double(
            forKey: CloudKitSchema.showModifiedKey(for: id)
        )
        return raw > 0 ? Date(timeIntervalSince1970: raw) : Date.distantPast
    }

    /// Re-queues records parked by `holdForQuota` once the account can write again.
    ///
    /// The gate is account availability alone. Testing `pauseReason != .quotaExceeded`
    /// could never pass: only `holdForQuota` fills this list, and it sets that very
    /// reason, so held records were stranded and the list never drained.
    func retryQuotaHeldIfNeeded() {
        guard account.isAccountAvailable,
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
