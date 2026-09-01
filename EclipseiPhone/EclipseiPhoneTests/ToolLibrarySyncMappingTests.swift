//
//  ToolLibrarySyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct ToolLibrarySyncMappingTests {

    @Test func backgroundSingletonRecordName() {
        let record = CloudKitRecordMapper.makeBackgroundRecord()
        #expect(record.recordType == CloudKitSchema.RecordType.background)
        #expect(record.recordID.recordName == CloudKitSchema.backgroundRecordName)
    }

    @Test func screensaverKindRoundTrip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try? Data([0xFF, 0xD8]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let record = CloudKitRecordMapper.makeScreensaverRecord(
            kind: "image",
            assetURL: url
        )
        #expect(CloudKitRecordMapper.screensaverKind(from: record) == "image")
        #expect(CloudKitRecordMapper.screensaverAssetURL(from: record) == url)
    }

    @Test func cameraSettingsRoundTrip() {
        let enabled = [UUID(), UUID()]
        let selected = enabled[0]
        let record = CloudKitRecordMapper.makeCameraSettingsRecord(
            orientation: .portrait,
            enabledIds: enabled,
            selectedId: selected
        )
        #expect(
            CloudKitRecordMapper.cameraSettingsOrientation(from: record) == .portrait
        )
        #expect(Set(CloudKitRecordMapper.cameraSettingsEnabledIds(from: record)) == Set(enabled))
        #expect(CloudKitRecordMapper.cameraSettingsSelectedId(from: record) == selected)
    }

    @Test func cutawayRecordUsesUUIDName() {
        let id = UUID()
        let record = CloudKitRecordMapper.makeCutawayRecord(
            id: id,
            createdAt: Date()
        )
        #expect(record.recordType == CloudKitSchema.RecordType.cutawayStill)
        #expect(record.recordID.recordName == id.uuidString)
    }
}
