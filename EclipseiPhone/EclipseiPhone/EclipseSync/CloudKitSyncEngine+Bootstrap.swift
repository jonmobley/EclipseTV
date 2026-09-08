//
//  CloudKitSyncEngine+Bootstrap.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Engine lifecycle + queue replay

extension CloudKitSyncEngine {

    /// Builds the private-database engine once an iCloud account is available.
    func bootstrapEngineIfPossible() async {
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

    func persistEngineState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    /// Enqueues dirty Shows, unacknowledged deletes, and pending child records.
    ///
    /// Does **not** stamp Show `modifiedAt` — inventing “now” on bootstrap/foreground
    /// would let an idle device win LWW over real offline edits on another phone.
    func enqueueAllLocal() {
        guard let engine else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        let ownedShowIds = LocalAlbumStore.shared.albums
            .map(\.id)
            .filter { !sharedZones.isSharedIn(showId: $0) }
        showDirty.seedIfNeeded(with: ownedShowIds)
        // Only Shows with unsent edits, and never a Show shared *to* this user:
        // re-saving one of those forks the owner's Show into our private zone.
        for id in ownedShowIds where showDirty.contains(id) {
            changes.append(.saveRecord(CloudKitSchema.showRecordID(for: id)))
        }
        enqueuePendingDeletes(into: &changes)
        enqueueMediaChanges(into: &changes)
        // Only PDFs the server hasn't acknowledged — a blanket re-enqueue would
        // re-upload every document's bytes on each launch.
        for id in PDFStore.shared.idsNeedingUpload {
            changes.append(.saveRecord(CloudKitSchema.pdfRecordID(for: id)))
        }
        enqueueExpandedLocalContent(into: &changes)
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    /// Enqueues MediaItem saves: assets awaiting upload, plus preference-only edits.
    ///
    /// Both registries funnel through here so a record that is *both* pending and
    /// dirty is queued once rather than twice.
    private func enqueueMediaChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        mediaDirty.seedIfNeeded(
            with: CaptureStore.shared.syncableIds + ImportedMediaStore.shared.syncableIds
        )
        var names = Set(CaptureStore.shared.idsNeedingUpload)
        names.formUnion(ImportedMediaStore.shared.idsNeedingUpload)
        names.formUnion(mediaDirty.allDirty)
        for name in names {
            changes.append(.saveRecord(CloudKitSchema.mediaRecordID(for: name)))
        }
    }

    /// Recreates the private library zone and re-enqueues local content.
    ///
    /// Used when the zone is deleted server-side or a save fails with `zoneNotFound`.
    /// Never deletes local data in response to that signal.
    func recoverFromZoneLoss() {
        guard let engine else { return }
        lastKnownRecords.removeAll()
        showDirty.markAllDirty(LocalAlbumStore.shared.albums.map(\.id))
        // The new zone has no assets, so media has to go back to `.pendingUpload`:
        // a `.synced` row would be re-saved metadata-only and land undownloadable.
        CaptureStore.shared.markAllNeedsUpload()
        ImportedMediaStore.shared.markAllNeedsUpload()
        CameraFrameStore.shared.markAllNeedsUpload()
        CameraAlternateStillStore.shared.markAllNeedsUpload()
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

    // MARK: - Local store observation

    func observeLocalStores() {
        storeObservers.append(NotificationCenter.default.addObserver(
            forName: LocalAlbumStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.reconcileShowsWithEngine(notification) }
        })
    }

    /// Schedules saves for the Show that changed, or every owned Show when unspecified.
    private func reconcileShowsWithEngine(_ notification: Notification) {
        // Shared-DB apply only sets the controller flag — check both so accepted
        // Shares don't fork into the private zone.
        guard engine != nil,
              !isApplyingRemote,
              !EclipseSyncController.shared.isApplyingRemote else { return }
        if let id = notification.userInfo?[LocalAlbumStore.changedAlbumIdKey] as? UUID {
            guard !sharedZones.isSharedIn(showId: id) else { return }
            scheduleShowSave(id: id)
            return
        }
        for album in LocalAlbumStore.shared.albums
        where !sharedZones.isSharedIn(showId: album.id) {
            scheduleShowSave(id: album.id)
        }
    }
}
