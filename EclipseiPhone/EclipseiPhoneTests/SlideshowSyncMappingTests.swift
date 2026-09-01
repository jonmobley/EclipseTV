//
//  SlideshowSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct SlideshowSyncMappingTests {

    @Test func recordRoundTripPreservesPrefsAndMembership() throws {
        let showId = UUID()
        let show = Slideshow(
            showId: showId,
            name: "Highlights",
            itemIds: ["a.jpg", "b.jpg"],
            coverId: "a.jpg",
            autoplay: true,
            autoplaySeconds: .ten,
            loop: true,
            crossfade: false,
            showRibbonWhenLive: true,
            isFill: true
        )
        let record = CloudKitRecordMapper.makeSlideshowRecord(from: show)
        #expect(record.recordType == CloudKitSchema.RecordType.slideshow)
        #expect(record.parent == nil)

        let decoded = try #require(CloudKitRecordMapper.slideshow(from: record))
        #expect(decoded.id == show.id)
        #expect(decoded.showId == showId)
        #expect(decoded.itemIds == ["a.jpg", "b.jpg"])
        #expect(decoded.autoplay == true)
        #expect(decoded.autoplaySeconds == .ten)
        #expect(decoded.loop == true)
        #expect(decoded.crossfade == false)
        #expect(decoded.showRibbonWhenLive == true)
        #expect(decoded.isFill == true)
    }

    @Test func shareChildSetsParent() throws {
        let showId = UUID()
        let show = Slideshow(showId: showId, name: "Shared", itemIds: ["x.jpg"])
        let record = CloudKitRecordMapper.makeSlideshowRecord(
            from: show,
            attachAsShareChild: true
        )
        let parent = try #require(record.parent)
        #expect(parent.recordID == CloudKitSchema.showRecordID(for: showId))
    }
}
