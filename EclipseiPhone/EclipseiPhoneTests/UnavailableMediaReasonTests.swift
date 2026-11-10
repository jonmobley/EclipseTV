//
//  UnavailableMediaReasonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct UnavailableMediaReasonTests {

    private func item(_ id: String, available: Bool?) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id,
            name: id,
            isVideo: false,
            duration: 0,
            isLooping: nil,
            isMuted: nil,
            isAvailable: available
        )
    }

    @Test func availableItemsHaveNoReason() {
        #expect(UnavailableMediaReason.of(item("a.jpg", available: nil), isSyncedThroughICloud: { _ in true }) == nil)
        #expect(UnavailableMediaReason.of(item("a.jpg", available: true), isSyncedThroughICloud: { _ in true }) == nil)
    }

    @Test func iCloudItemIsDownloadingNotMissingOnTV() {
        let reason = UnavailableMediaReason.of(
            item("cloud.jpg", available: false),
            isSyncedThroughICloud: { $0 == "cloud.jpg" }
        )
        #expect(reason == .waitingForICloud)
    }

    @Test func purgedTVItemIsMissingOnTV() {
        let reason = UnavailableMediaReason.of(
            item("tv.jpg", available: false),
            isSyncedThroughICloud: { _ in false }
        )
        #expect(reason == .missingOnAppleTV)
    }
}
