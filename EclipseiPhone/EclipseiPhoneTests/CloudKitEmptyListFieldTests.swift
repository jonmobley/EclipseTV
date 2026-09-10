//
//  CloudKitEmptyListFieldTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

/// CloudKit rejects an empty list written to a field it has not typed yet
/// ("cannot use an empty list to initialize a new field"), and the rejection fails the
/// whole record — so a Show with nothing deleted stopped a device syncing at all.
/// Empty list fields are therefore cleared rather than written.
struct CloudKitEmptyListFieldTests {

    @Test func showRecordOmitsEmptyListFields() {
        let record = CloudKitRecordMapper.makeShowRecord(from: album(itemIds: []))
        #expect(record[CloudKitSchema.ShowKey.itemIds] == nil)
        #expect(record[CloudKitSchema.ShowKey.deletedItemIds] == nil)
        #expect(record[CloudKitSchema.ShowKey.deletedSurfaceIds] == nil)
    }

    @Test func showRecordStillWritesPopulatedListFields() {
        var subject = album(itemIds: ["a.jpg", "b.jpg"])
        subject.deletedItemIds = ["gone.jpg"]
        subject.deletedSurfaceIds = ["tool.camera"]
        let record = CloudKitRecordMapper.makeShowRecord(from: subject)
        #expect(record[CloudKitSchema.ShowKey.itemIds] as? [String] == ["a.jpg", "b.jpg"])
        #expect(
            record[CloudKitSchema.ShowKey.deletedItemIds] as? [String] == ["gone.jpg"]
        )
        #expect(
            record[CloudKitSchema.ShowKey.deletedSurfaceIds] as? [String]
                == ["tool.camera"]
        )
    }

    @Test func clearingAListFieldSurvivesAnUpdateToAnExistingRecord() {
        var subject = album(itemIds: ["a.jpg"])
        subject.deletedItemIds = ["gone.jpg"]
        let record = CloudKitRecordMapper.makeShowRecord(from: subject)
        subject.deletedItemIds = []
        let updated = CloudKitRecordMapper.makeShowRecord(from: subject, existing: record)
        #expect(updated === record)
        #expect(updated[CloudKitSchema.ShowKey.deletedItemIds] == nil)
    }

    @Test func emptySurfaceOrderIsNotConfusedWithNoOrder() {
        // `resolvedSurfaceIds` falls back to tools-then-members only when the field is
        // absent, so an explicit ordering must not be flattened to nil.
        var subject = album(itemIds: ["a.jpg"])
        subject.surfaceIds = ["a.jpg"]
        let record = CloudKitRecordMapper.makeShowRecord(from: subject)
        #expect(record[CloudKitSchema.ShowKey.surfaceIds] as? [String] == ["a.jpg"])
    }

    @Test func showRecordRoundTripsThroughAnOmittedField() throws {
        let record = CloudKitRecordMapper.makeShowRecord(from: album(itemIds: []))
        let decoded = try #require(CloudKitRecordMapper.album(from: record))
        #expect(decoded.itemIds.isEmpty)
        #expect(decoded.deletedItemIds.isEmpty)
        #expect(decoded.deletedSurfaceIds.isEmpty)
    }

    @Test func slideshowRecordOmitsAnEmptyItemList() {
        let show = Slideshow(id: UUID(), showId: UUID(), name: "Empty", itemIds: [])
        let record = CloudKitRecordMapper.makeSlideshowRecord(from: show)
        #expect(record[CloudKitSchema.SlideshowKey.itemIds] == nil)
    }

    @Test func cameraSettingsRecordOmitsAnEmptyEnabledList() {
        let record = CloudKitRecordMapper.makeCameraSettingsRecord(
            orientation: .landscape,
            enabledIds: [],
            selectedId: nil
        )
        #expect(record[CloudKitSchema.CameraSettingsKey.enabledIds] == nil)
        #expect(CloudKitRecordMapper.cameraSettingsEnabledIds(from: record).isEmpty)
    }

    private func album(itemIds: [String]) -> LocalAlbum {
        LocalAlbum(id: UUID(), name: "Show", itemIds: itemIds)
    }
}
