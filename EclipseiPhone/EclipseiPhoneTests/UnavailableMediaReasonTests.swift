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
        #expect(UnavailableMediaReason.of(item("a.jpg", available: nil), iCloudState: { _ in .remoteOnly }) == nil)
        #expect(UnavailableMediaReason.of(item("a.jpg", available: true), iCloudState: { _ in .remoteOnly }) == nil)
    }

    /// Not on the phone and nothing fetching it: the tile must not claim a download.
    @Test func iCloudItemNotDownloadingIsInICloud() {
        let reason = UnavailableMediaReason.of(
            item("cloud.jpg", available: false),
            iCloudState: { $0 == "cloud.jpg" ? .remoteOnly : nil }
        )
        #expect(reason == .inICloud)
        #expect(reason?.pillTitle == "In iCloud")
    }

    @Test func iCloudItemInFlightIsDownloading() {
        let reason = UnavailableMediaReason.of(
            item("cloud.jpg", available: false),
            iCloudState: { _ in .downloading }
        )
        #expect(reason == .downloading)
        #expect(reason?.pillTitle == "Downloading…")
    }

    @Test func purgedTVItemIsMissingOnTV() {
        let reason = UnavailableMediaReason.of(
            item("tv.jpg", available: false),
            iCloudState: { _ in nil }
        )
        #expect(reason == .missingOnAppleTV)
        #expect(reason?.isICloud == false)
    }

    @Test func downloadingHasNoLocalFile() {
        #expect(!CaptureSyncState.downloading.hasLocalFile)
        #expect(!CaptureSyncState.remoteOnly.hasLocalFile)
        #expect(CaptureSyncState.synced.hasLocalFile)
        #expect(CaptureSyncState.pendingUpload.hasLocalFile)
        #expect(CaptureSyncState.localOnly.hasLocalFile)
    }
}
