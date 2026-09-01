//
//  CloudKitSyncEngine+Schedule.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Additional SyncBackend schedules

extension CloudKitSyncEngine {

    func scheduleMediaSave(cloudId: String) {
        guard let engine else { return }
        ImportedMediaStore.shared.setSyncState(id: cloudId, .pendingUpload)
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.mediaRecordID(for: cloudId))
        ])
    }

    func scheduleMediaDelete(cloudId: String) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.mediaRecordID(for: cloudId))
        ])
    }

    func scheduleWebPageSave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.webPageRecordID(for: id))
        ])
    }

    func scheduleWebPageDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.webPageRecordID(for: id))
        ])
    }

    func scheduleSlideshowSave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.slideshowRecordID(for: id))
        ])
    }

    func scheduleSlideshowDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.slideshowRecordID(for: id))
        ])
    }

    func scheduleCountdownSave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.countdownRecordID(for: id))
        ])
    }

    func scheduleCountdownDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.countdownRecordID(for: id))
        ])
    }

    func scheduleLivePollSave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.livePollRecordID(for: id))
        ])
    }

    func scheduleLivePollDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.livePollRecordID(for: id))
        ])
    }

    func scheduleBackgroundSave() {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.backgroundRecordID)
        ])
    }

    func scheduleBackgroundDelete() {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.backgroundRecordID)
        ])
    }

    func scheduleScreensaverSave() {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.screensaverRecordID)
        ])
    }

    func scheduleScreensaverDelete() {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.screensaverRecordID)
        ])
    }

    func scheduleCameraFrameSave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.cameraFrameRecordID(for: id))
        ])
    }

    func scheduleCameraFrameDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.cameraFrameRecordID(for: id))
        ])
    }

    func scheduleCameraSettingsSave(orientation: ExternalOutputOrientation) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.cameraSettingsRecordID(for: orientation))
        ])
    }

    func scheduleCutawaySave(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .saveRecord(CloudKitSchema.cutawayRecordID(for: id))
        ])
    }

    func scheduleCutawayDelete(id: UUID) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudKitSchema.cutawayRecordID(for: id))
        ])
    }
}
