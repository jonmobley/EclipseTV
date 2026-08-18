//
//  LibraryAlbumPush.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Builds the Show → TV album snapshot sent over Multipeer.
enum LibraryAlbumPush {

    /// Every Show that still has at least one TV-sendable member, both orientations.
    @MainActor
    static func currentAlbums() -> [LibraryAlbumDTO] {
        LocalAlbumStore.shared.albums.compactMap { album in
            let ids = album.itemIds.filter(isTVSendable)
            guard !ids.isEmpty else { return nil }
            let cover = album.resolvedCoverId.flatMap { ids.contains($0) ? $0 : ids.first }
            return LibraryAlbumDTO(
                id: album.id.uuidString,
                name: album.name,
                itemIds: ids,
                coverId: cover,
                libraryMode: album.orientation.libraryMode.rawValue
            )
        }
    }

    /// Media the Eclipse TV library can actually display.
    @MainActor
    static func isTVSendable(_ id: String) -> Bool {
        guard !ShowToolToken.isTool(id) else { return false }
        guard !CaptureStore.shared.contains(id: id) else { return false }
        guard !WebPageStore.shared.keepIds.contains(id) else { return false }
        guard !PDFStore.shared.keepIds.contains(id) else { return false }
        if LocalMediaStore.shared.hasMedia(forId: id, mode: .landscape) { return true }
        if LocalMediaStore.shared.hasMedia(forId: id, mode: .vertical) { return true }
        return TVLibraryStore.shared.items.contains { $0.id == id }
    }
}
