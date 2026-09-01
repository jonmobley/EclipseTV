//
//  CountdownSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct CountdownSyncMappingTests {

    @Test func recordRoundTripPreservesNameAndDuration() throws {
        let showId = UUID()
        let item = ShowCountdown(
            showId: showId,
            name: "Intermission",
            duration: 450
        )
        let record = CloudKitRecordMapper.makeCountdownRecord(from: item)
        #expect(record.recordType == CloudKitSchema.RecordType.countdown)
        #expect(record.parent == nil)

        let decoded = try #require(CloudKitRecordMapper.countdown(from: record))
        #expect(decoded.id == item.id)
        #expect(decoded.showId == showId)
        #expect(decoded.name == "Intermission")
        #expect(decoded.duration == 450)
    }

    @Test func shareChildSetsParent() throws {
        let showId = UUID()
        let item = ShowCountdown(showId: showId, name: "Shared", duration: 60)
        let record = CloudKitRecordMapper.makeCountdownRecord(
            from: item,
            attachAsShareChild: true
        )
        let parent = try #require(record.parent)
        #expect(parent.recordID == CloudKitSchema.showRecordID(for: showId))
    }
}
