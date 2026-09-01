//
//  CloudKitRecordReuseTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct CloudKitRecordReuseTests {

    @Test func cameraSettingsSaveKeepsExistingRecordIdentity() {
        let orientation = ExternalOutputOrientation.landscape
        let existing = CKRecord(
            recordType: CloudKitSchema.RecordType.cameraSettings,
            recordID: CloudKitSchema.cameraSettingsRecordID(for: orientation)
        )
        let updated = CloudKitRecordMapper.makeCameraSettingsRecord(
            orientation: orientation,
            enabledIds: [],
            selectedId: nil,
            existing: existing
        )
        #expect(updated === existing)
    }

    @Test func cameraFrameSaveKeepsExistingRecordIdentity() {
        let id = UUID()
        let existing = CKRecord(
            recordType: CloudKitSchema.RecordType.cameraFrame,
            recordID: CloudKitSchema.cameraFrameRecordID(for: id)
        )
        let updated = CloudKitRecordMapper.makeCameraFrameRecord(
            id: id,
            orientation: .portrait,
            createdAt: Date(),
            existing: existing
        )
        #expect(updated === existing)
    }

    @Test func cameraSettingsInsertHasNoExistingRecord() {
        let record = CloudKitRecordMapper.makeCameraSettingsRecord(
            orientation: .portrait,
            enabledIds: [],
            selectedId: nil
        )
        #expect(record.recordChangeTag == nil)
        #expect(
            record.recordID.recordName == "eclipse.cameraSettings.Vertical"
        )
    }
}
