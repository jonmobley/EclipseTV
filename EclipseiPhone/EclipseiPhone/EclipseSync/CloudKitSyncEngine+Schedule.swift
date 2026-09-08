//
//  CloudKitSyncEngine+Schedule.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Queue primitives

extension CloudKitSyncEngine {

    /// Enqueues a save and cancels any unacknowledged delete for the same id.
    ///
    /// Singleton records (Background, Screensaver) can be cleared and set again, so
    /// a stale pending delete would otherwise race the new save on next bootstrap.
    func scheduleSave(_ recordID: CKRecord.ID) {
        pendingDeletes.clear(recordID.recordName)
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    /// Persists the intent to delete, then enqueues it when an engine exists.
    ///
    /// Recording before the engine check is the point: a delete made while signed
    /// out is replayed by `enqueueAllLocal` instead of being silently dropped.
    func scheduleDelete(_ recordID: CKRecord.ID) {
        pendingDeletes.note(recordID.recordName)
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    /// Re-enqueues deletes CloudKit has not acknowledged yet.
    func enqueuePendingDeletes(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        for name in pendingDeletes.recordNames {
            changes.append(
                .deleteRecord(CKRecord.ID(recordName: name, zoneID: CloudKitSchema.zoneID))
            )
        }
    }
}

// MARK: - Additional SyncBackend schedules

extension CloudKitSyncEngine {

    func scheduleMediaSave(cloudId: String) {
        ImportedMediaStore.shared.setSyncState(id: cloudId, .pendingUpload)
        scheduleSave(CloudKitSchema.mediaRecordID(for: cloudId))
    }

    func scheduleMediaDelete(cloudId: String) {
        scheduleDelete(CloudKitSchema.mediaRecordID(for: cloudId))
    }

    /// Schedules a metadata-only save after a Fit / framing / loop / mute edit.
    ///
    /// Deliberately leaves `syncState` alone: flipping to `.pendingUpload` would make
    /// `CloudKitAssetUploadPolicy` re-attach the `CKAsset` and re-upload the whole
    /// file for what is a few bytes of preference change.
    ///
    /// `libraryId` is the library file name the settings helpers key on, which is not
    /// the MediaItem record name, so it has to be resolved through the registries.
    func scheduleMediaPrefsSave(libraryId: String) {
        guard !isApplyingRemote,
              !EclipseSyncController.shared.isApplyingRemote else { return }
        guard let recordName = mediaRecordName(forAnyId: libraryId) else { return }
        mediaDirty.markDirty(recordName)
        scheduleSave(CloudKitSchema.mediaRecordID(for: recordName))
    }

    /// MediaItem record name for either a record name or a library file name.
    ///
    /// Both registries match on either form, so this normalises the mixed ids that
    /// reach the backend into the one key CloudKit and the eviction index use.
    func mediaRecordName(forAnyId id: String) -> String? {
        if let capture = CaptureStore.shared.record(id: id) {
            return capture.id
        }
        return ImportedMediaStore.shared.record(id: id)?.cloudId
    }

    func scheduleWebPageSave(id: UUID) {
        scheduleSave(CloudKitSchema.webPageRecordID(for: id))
    }

    func scheduleWebPageDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.webPageRecordID(for: id))
    }

    func scheduleSlideshowSave(id: UUID) {
        scheduleSave(CloudKitSchema.slideshowRecordID(for: id))
    }

    func scheduleSlideshowDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.slideshowRecordID(for: id))
    }

    func scheduleCountdownSave(id: UUID) {
        scheduleSave(CloudKitSchema.countdownRecordID(for: id))
    }

    func scheduleCountdownDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.countdownRecordID(for: id))
    }

    func scheduleLivePollSave(id: UUID) {
        scheduleSave(CloudKitSchema.livePollRecordID(for: id))
    }

    func scheduleLivePollDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.livePollRecordID(for: id))
    }

    func scheduleBackgroundSave() {
        scheduleSave(CloudKitSchema.backgroundRecordID)
    }

    func scheduleBackgroundDelete() {
        scheduleDelete(CloudKitSchema.backgroundRecordID)
    }

    func scheduleScreensaverSave() {
        scheduleSave(CloudKitSchema.screensaverRecordID)
    }

    func scheduleScreensaverDelete() {
        scheduleDelete(CloudKitSchema.screensaverRecordID)
    }

    func scheduleCameraFrameSave(id: UUID) {
        scheduleSave(CloudKitSchema.cameraFrameRecordID(for: id))
    }

    func scheduleCameraFrameDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.cameraFrameRecordID(for: id))
    }

    func scheduleCameraSettingsSave(orientation: ExternalOutputOrientation) {
        scheduleSave(CloudKitSchema.cameraSettingsRecordID(for: orientation))
    }

    func scheduleCutawaySave(id: UUID) {
        scheduleSave(CloudKitSchema.cutawayRecordID(for: id))
    }

    func scheduleCutawayDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.cutawayRecordID(for: id))
    }
}
