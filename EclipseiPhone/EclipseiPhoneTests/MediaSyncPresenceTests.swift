//
//  MediaSyncPresenceTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// `isAvailable == false` means two different things; the tile must tell them apart.
struct MediaSyncPresenceTests {

    // MARK: - Resolution

    @Test func aPlainTVItemWithoutAFileIsPurged() {
        #expect(
            MediaSyncPresence.resolve(syncState: nil, isAvailable: false) == .purgedOnTV
        )
    }

    @Test func aPlainTVItemWithAFileIsLocal() {
        #expect(MediaSyncPresence.resolve(syncState: nil, isAvailable: true) == .local)
        #expect(MediaSyncPresence.resolve(syncState: nil, isAvailable: nil) == .local)
    }

    @Test func remoteOnlyReadsAsInCloudNotUnavailable() {
        #expect(
            MediaSyncPresence.resolve(syncState: .remoteOnly, isAvailable: false) == .inCloud
        )
    }

    @Test func downloadingWinsOverTheDTOFlag() {
        #expect(
            MediaSyncPresence.resolve(syncState: .downloading, isAvailable: false)
                == .downloading
        )
    }

    @Test func pendingUploadOnlyBadgesWhileSyncIsActive() {
        #expect(
            MediaSyncPresence.resolve(
                syncState: .pendingUpload, isAvailable: true, isSyncActive: true
            ) == .pendingUpload
        )
        #expect(
            MediaSyncPresence.resolve(
                syncState: .pendingUpload, isAvailable: true, isSyncActive: false
            ) == .local
        )
    }

    @Test func syncedBytesDeferToTheTVFlag() {
        #expect(MediaSyncPresence.resolve(syncState: .synced, isAvailable: true) == .local)
        #expect(
            MediaSyncPresence.resolve(syncState: .synced, isAvailable: false) == .purgedOnTV
        )
    }

    @Test func onlyCloudStatesAskForADownload() {
        #expect(MediaSyncPresence.inCloud.wantsCloudDownload)
        #expect(MediaSyncPresence.downloading.wantsCloudDownload)
        #expect(!MediaSyncPresence.purgedOnTV.wantsCloudDownload)
        #expect(!MediaSyncPresence.pendingUpload.wantsCloudDownload)
        #expect(!MediaSyncPresence.local.wantsCloudDownload)
    }

    // MARK: - Tile chrome

    @MainActor
    @Test func inCloudTileSaysSoAndDimsLessThanAPurgedOne() {
        let cell = makeCell()
        cell.configure(
            with: item(), thumbnail: swatch(), isLive: false, syncPresence: .inCloud
        )
        #expect(cell.syncPillText == "In iCloud")
        #expect(cell.uploadBadge.isHidden)
        #expect(cell.accessibilityLabel?.hasSuffix("in iCloud") == true)
        let inCloudAlpha = cell.imageView.alpha

        cell.configure(
            with: item(), thumbnail: swatch(), isLive: false, syncPresence: .purgedOnTV
        )
        #expect(cell.syncPillText == "Unavailable")
        #expect(cell.imageView.alpha < inCloudAlpha)
        #expect(cell.accessibilityLabel?.hasSuffix("unavailable") == true)
    }

    @MainActor
    @Test func downloadingTileShowsAPill() {
        let cell = makeCell()
        cell.configure(
            with: item(), thumbnail: swatch(), isLive: true, syncPresence: .downloading
        )
        #expect(cell.syncPillText == "Downloading…")
        // Bytes aren't here yet, so the tile can't carry the live stroke.
        #expect(cell.cardView.layer.borderWidth == 0)
    }

    @MainActor
    @Test func pendingUploadShowsTheCornerBadgeAndNoPill() {
        let cell = makeCell()
        cell.configure(
            with: item(), thumbnail: swatch(), isLive: false, syncPresence: .pendingUpload
        )
        #expect(cell.syncPillText == nil)
        #expect(cell.uploadBadge.isHidden == false)
        #expect(cell.imageView.alpha == 1)
        #expect(cell.accessibilityLabel?.hasSuffix("waiting to upload") == true)
    }

    @MainActor
    @Test func rewindCoversTheUploadBadge() {
        let cell = makeCell()
        cell.configure(
            with: item(isVideo: true), thumbnail: swatch(), isLive: false,
            syncPresence: .pendingUpload
        )
        #expect(cell.uploadBadge.isHidden == false)
        cell.setRewindHandler {}
        #expect(cell.uploadBadge.isHidden)
        cell.setRewindHandler(nil)
        #expect(cell.uploadBadge.isHidden == false)
    }

    @MainActor
    @Test func localTileCarriesNoPresenceChrome() {
        let cell = makeCell()
        cell.configure(
            with: item(), thumbnail: swatch(), isLive: false, syncPresence: .local
        )
        #expect(cell.syncPillText == nil)
        #expect(cell.uploadBadge.isHidden)
        #expect(cell.imageView.alpha == 1)
    }

    @MainActor
    @Test func reuseClearsThePill() {
        let cell = makeCell()
        cell.configure(
            with: item(), thumbnail: swatch(), isLive: false, syncPresence: .inCloud
        )
        cell.prepareForReuse()
        #expect(cell.syncPillText == nil)
        #expect(cell.uploadBadge.isHidden)
    }

    // MARK: - Stale downloads

    @MainActor
    @Test func aCaptureLeftDownloadingReloadsAsRemoteOnly() throws {
        let suite = "MediaSyncPresenceTests.captures.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = CaptureStore(defaults: defaults)
        first.upsert(CaptureRecord(id: "stuck", isVideo: false, fileExtension: "jpg"))
        first.setSyncState(id: "stuck", .downloading)

        let relaunched = CaptureStore(defaults: defaults)
        #expect(relaunched.record(id: "stuck")?.syncState == .remoteOnly)
    }

    @MainActor
    @Test func anImportLeftDownloadingReloadsAsRemoteOnly() throws {
        let suite = "MediaSyncPresenceTests.imports.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ImportedMediaStore(defaults: defaults)
        let imported = first.register(
            libraryId: "stuck.jpg", isVideo: false, duration: 0,
            orientation: .landscape, showId: nil
        )
        first.setSyncState(id: imported.cloudId, .downloading)

        let relaunched = ImportedMediaStore(defaults: defaults)
        #expect(relaunched.record(id: imported.cloudId)?.syncState == .remoteOnly)
    }

    // MARK: - Helpers

    @MainActor
    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    private func item(isVideo: Bool = false) -> LibraryItemDTO {
        LibraryItemDTO(
            id: "presence-test-\(UUID().uuidString).\(isVideo ? "mov" : "jpg")",
            name: "IMG_2000",
            isVideo: isVideo,
            duration: isVideo ? 12 : 0,
            isAvailable: true
        )
    }

    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
