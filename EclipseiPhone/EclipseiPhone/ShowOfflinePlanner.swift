//
//  ShowOfflinePlanner.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Which photos and videos a Show needs on this iPhone to present without internet.
///
/// PDFs always keep their file on the phone, and websites, polls, and tools need the
/// network anyway, so only library media can be missing: a Show's own photos and
/// videos, its slideshow slides, and its countdown backgrounds.
enum ShowOfflinePlanner {

    /// One Show-grid tile, reduced to the media it needs.
    enum Tile: Equatable {
        case media(id: String)
        case slideshow(slideIds: [String])
        case countdown(backgroundId: String?)
        case other
    }

    /// Library media ids in grid order, each once.
    static func mediaIds(in tiles: [Tile]) -> [String] {
        var seen: Set<String> = []
        var ids: [String] = []
        func add(_ id: String) {
            guard !id.isEmpty, seen.insert(id).inserted else { return }
            ids.append(id)
        }
        for tile in tiles {
            switch tile {
            case .media(let id): add(id)
            case .slideshow(let slideIds): slideIds.forEach(add)
            case .countdown(let backgroundId): backgroundId.map(add)
            case .other: break
            }
        }
        return ids
    }
}

// MARK: - Store lookups

extension ShowOfflinePlanner {

    /// Ids of the Show's photos and videos that are in iCloud but not on this iPhone.
    @MainActor
    static func idsToDownload(forShowId showId: UUID) -> [String] {
        guard let album = LocalAlbumStore.shared.album(id: showId) else { return [] }
        return mediaIds(in: tiles(for: album)).filter(isCloudOnly)
    }

    @MainActor
    static func tiles(for album: LocalAlbum) -> [Tile] {
        let slideshows = SlideshowStore.shared.slideshows(forShowId: album.id)
        let countdowns = CountdownStore.shared.countdowns(forShowId: album.id)
        let surface = album.resolvedSurfaceIds(
            slideshowIds: slideshows.map { ShowSlideshowToken.token(for: $0.id) },
            countdownIds: countdowns.map { ShowCountdownToken.token(for: $0.id) },
            livePollIds: nil
        )
        return surface.map { tile(for: $0, showId: album.id) }
    }

    @MainActor
    private static func tile(for surfaceId: String, showId: UUID) -> Tile {
        if let id = ShowSlideshowToken.slideshowId(from: surfaceId) {
            guard let show = SlideshowStore.shared.slideshow(id: id), show.showId == showId
            else { return .other }
            return .slideshow(slideIds: show.itemIds)
        }
        if let id = ShowCountdownToken.countdownId(from: surfaceId) {
            let clock = CountdownStore.shared.countdown(id: id)
            return .countdown(backgroundId: clock?.background.libraryItemId)
        }
        if ShowToolToken.isTool(surfaceId) || ShowLivePollToken.isLivePoll(surfaceId) {
            return .other
        }
        if let uuid = UUID(uuidString: surfaceId),
           WebPageStore.shared.page(id: uuid) != nil
            || PDFStore.shared.documents.contains(where: { $0.id == uuid }) {
            return .other
        }
        return .media(id: surfaceId)
    }

    /// In iCloud, with no file on this iPhone. Media that never reached iCloud
    /// (or only lives on a linked Apple TV) can't be fetched, so it isn't counted.
    @MainActor
    private static func isCloudOnly(_ id: String) -> Bool {
        if let capture = CaptureStore.shared.record(id: id) {
            guard capture.syncState != .localOnly else { return false }
            return !LocalMediaStore.shared.hasMedia(
                forId: capture.libraryFileName, mode: capture.orientation.libraryMode
            )
        }
        if let imported = ImportedMediaStore.shared.record(id: id) {
            guard imported.syncState != .localOnly else { return false }
            return !LocalMediaStore.shared.hasMedia(
                forId: imported.libraryId, mode: imported.orientation.libraryMode
            )
        }
        return false
    }
}
