//
//  MediaSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct MediaSyncMappingTests {

    @Test func showIdFieldDoesNotSetParentByDefault() {
        let showId = UUID()
        let capture = CaptureRecord(
            isVideo: false,
            showId: showId,
            fileExtension: "jpg"
        )
        let record = CloudKitRecordMapper.makeMediaRecord(from: capture)
        #expect(record[CloudKitSchema.MediaKey.showId] as? String == showId.uuidString)
        #expect(record.parent == nil)
    }

    @Test func shareChildSetsParentToShow() throws {
        let showId = UUID()
        let capture = CaptureRecord(
            isVideo: false,
            showId: showId,
            fileExtension: "jpg"
        )
        let record = CloudKitRecordMapper.makeMediaRecord(
            from: capture,
            attachAsShareChild: true
        )
        let parent = try #require(record.parent)
        #expect(parent.recordID == CloudKitSchema.showRecordID(for: showId))
    }

    @Test func attachWithoutShowIdLeavesParentNil() {
        let capture = CaptureRecord(isVideo: false, fileExtension: "jpg")
        let record = CloudKitRecordMapper.makeMediaRecord(
            from: capture,
            attachAsShareChild: true
        )
        #expect(record.parent == nil)
        #expect(record[CloudKitSchema.MediaKey.showId] == nil)
    }

    @Test func omittingShareChildClearsExistingParent() {
        let showId = UUID()
        let capture = CaptureRecord(
            isVideo: false,
            showId: showId,
            fileExtension: "jpg"
        )
        let withParent = CloudKitRecordMapper.makeMediaRecord(
            from: capture,
            attachAsShareChild: true
        )
        #expect(withParent.parent != nil)
        let stripped = CloudKitRecordMapper.makeMediaRecord(
            from: capture,
            existing: withParent,
            attachAsShareChild: false
        )
        #expect(stripped.parent == nil)
    }

    @Test func explicitShowIdOverridesCapture() {
        let captureShow = UUID()
        let membership = UUID()
        let capture = CaptureRecord(
            isVideo: false,
            showId: captureShow,
            fileExtension: "jpg"
        )
        let record = CloudKitRecordMapper.makeMediaRecord(
            from: capture,
            showId: membership
        )
        #expect(
            record[CloudKitSchema.MediaKey.showId] as? String
                == membership.uuidString
        )
    }
}
