//
//  CloudKitSyncEngine+Conflict.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Save acknowledgements + conflicts

extension CloudKitSyncEngine {

    /// Clears local dirty flags after CloudKit accepts a save (or already has it).
    func markLocalRecordSynced(_ record: CKRecord) {
        let name = record.recordID.recordName
        switch record.recordType {
        case CloudKitSchema.RecordType.mediaItem:
            if CloudKitRecordMapper.isImportedMedia(record) {
                ImportedMediaStore.shared.setSyncState(id: name, .synced)
            } else {
                CaptureStore.shared.setSyncState(id: name, .synced)
            }
        case CloudKitSchema.RecordType.pdfDoc:
            if let uuid = UUID(uuidString: name) {
                PDFStore.shared.markSynced(id: uuid)
            }
        case CloudKitSchema.RecordType.webPage:
            if let uuid = UUID(uuidString: name) {
                WebPageStore.shared.markSynced(id: uuid)
            }
        case CloudKitSchema.RecordType.slideshow:
            if let uuid = UUID(uuidString: name) {
                SlideshowStore.shared.markSynced(id: uuid)
            }
        case CloudKitSchema.RecordType.countdown:
            if let uuid = UUID(uuidString: name) {
                CountdownStore.shared.markSynced(id: uuid)
            }
        case CloudKitSchema.RecordType.livePoll:
            if let uuid = UUID(uuidString: name) {
                LivePollStore.shared.markSynced(id: uuid)
            }
        case CloudKitSchema.RecordType.cameraFrame:
            if let uuid = UUID(uuidString: name) {
                CameraFrameStore.shared.markFrameSynced(id: uuid)
            }
        case CloudKitSchema.RecordType.cameraSettings:
            CameraFrameStore.shared.markSettingsSynced(recordName: name)
        case CloudKitSchema.RecordType.cutawayStill:
            if let uuid = UUID(uuidString: name) {
                CameraAlternateStillStore.shared.markSynced(id: uuid)
            }
        default:
            break
        }
    }

    /// Re-queues after a server conflict, overlaying local fields onto the server record.
    func mergeConflictAndRequeueExpanded(record: CKRecord, error: CKError) {
        guard let server = error.serverRecord else {
            engine?.state.remove(pendingRecordZoneChanges: [
                .saveRecord(record.recordID)
            ])
            markLocalRecordSynced(record)
            logger.error(
                "Dropped pending save; server record already exists for \(record.recordID.recordName, privacy: .public)"
            )
            return
        }
        rememberLastKnown(server)
        isApplyingRemote = true
        EclipseSyncController.shared.isApplyingRemote = true
        defer {
            isApplyingRemote = false
            EclipseSyncController.shared.isApplyingRemote = false
        }
        scheduleSaveAfterConflict(server)
    }

    /// Applies the server copy, then re-queues a tagged update of local fields.
    func scheduleSaveAfterConflict(_ server: CKRecord) {
        applyConflictWinner(server)
        requeueConflictSave(server)
    }

    private func applyConflictWinner(_ server: CKRecord) {
        if server.recordType == CloudKitSchema.RecordType.show {
            applyRemoteShow(server)
        } else {
            applyChildRecord(server)
        }
    }

    private func requeueConflictSave(_ server: CKRecord) {
        let name = server.recordID.recordName
        switch server.recordType {
        case CloudKitSchema.RecordType.show:
            if let uuid = UUID(uuidString: name) { scheduleShowSave(id: uuid) }
        case CloudKitSchema.RecordType.pdfDoc:
            if let uuid = UUID(uuidString: name) { schedulePDFSave(id: uuid) }
        case CloudKitSchema.RecordType.mediaItem:
            if CloudKitRecordMapper.isImportedMedia(server) {
                scheduleMediaSave(cloudId: name)
            } else {
                scheduleCaptureSave(id: name)
            }
        case CloudKitSchema.RecordType.webPage:
            if let uuid = UUID(uuidString: name) { scheduleWebPageSave(id: uuid) }
        case CloudKitSchema.RecordType.slideshow:
            if let uuid = UUID(uuidString: name) { scheduleSlideshowSave(id: uuid) }
        case CloudKitSchema.RecordType.countdown:
            if let uuid = UUID(uuidString: name) { scheduleCountdownSave(id: uuid) }
        case CloudKitSchema.RecordType.livePoll:
            if let uuid = UUID(uuidString: name) { scheduleLivePollSave(id: uuid) }
        case CloudKitSchema.RecordType.background:
            scheduleBackgroundSave()
        case CloudKitSchema.RecordType.screensaver:
            scheduleScreensaverSave()
        case CloudKitSchema.RecordType.cameraFrame:
            if let uuid = UUID(uuidString: name) { scheduleCameraFrameSave(id: uuid) }
        case CloudKitSchema.RecordType.cameraSettings:
            if let orientation = CloudKitRecordMapper.cameraSettingsOrientation(
                from: server
            ) {
                scheduleCameraSettingsSave(orientation: orientation)
            }
        case CloudKitSchema.RecordType.cutawayStill:
            if let uuid = UUID(uuidString: name) { scheduleCutawaySave(id: uuid) }
        default:
            logger.error(
                "Unhandled conflict type \(server.recordType, privacy: .public)"
            )
        }
    }
}
