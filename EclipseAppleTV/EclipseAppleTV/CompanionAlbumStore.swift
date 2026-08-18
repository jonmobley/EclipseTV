//
//  CompanionAlbumStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Combine
import Foundation
import os.log

/// Phone Show groupings mirrored onto the TV as albums.
///
/// Metadata only — media files stay in `Caches/Media` under `MediaDataSource`.
/// An older companion that never sends `set_library_albums` leaves this empty,
/// and the grid stays a flat library.
final class CompanionAlbumStore: ObservableObject {

    static let shared = CompanionAlbumStore()

    /// Posted after `replaceAll` so the grid can rebuild album home.
    static let didChangeNotification = Notification.Name("CompanionAlbumStore.didChange")

    @Published private(set) var albums: [LibraryAlbumDTO] = []

    private let defaults: UserDefaults
    private let storageKey = "EclipseTV.companionAlbums"
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "CompanionAlbums")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Replaces the full album snapshot from the companion.
    func replaceAll(_ incoming: [LibraryAlbumDTO]) {
        albums = incoming
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        logger.info("Companion albums updated: \(incoming.count)")
    }

    /// Albums that belong to `mode` and still name at least one live library id.
    func displayAlbums(
        for mode: EclipseShareProtocol.LibraryMode,
        liveIds: Set<String>
    ) -> [LibraryAlbumDTO] {
        albums.filter { album in
            EclipseShareProtocol.LibraryMode.resolved(from: album.libraryMode) == mode
                && album.itemIds.contains(where: { liveIds.contains($0) })
        }
        .map { album in
            var copy = album
            copy.itemIds = album.itemIds.filter { liveIds.contains($0) }
            return copy
        }
    }

    /// Library ids not mentioned in any display album for `mode`.
    func leftoverIds(
        liveIds: [String],
        for mode: EclipseShareProtocol.LibraryMode
    ) -> [String] {
        let claimed = Set(
            displayAlbums(for: mode, liveIds: Set(liveIds)).flatMap(\.itemIds)
        )
        return liveIds.filter { !claimed.contains($0) }
    }

    /// First album in `mode` that contains `itemId`, if any.
    func album(
        containing itemId: String,
        mode: EclipseShareProtocol.LibraryMode,
        liveIds: Set<String>
    ) -> LibraryAlbumDTO? {
        displayAlbums(for: mode, liveIds: liveIds)
            .first { $0.itemIds.contains(itemId) }
    }

    /// Album with `id` after filtering to `liveIds` in its mode.
    func displayAlbum(id: String, liveIds: Set<String>) -> LibraryAlbumDTO? {
        guard let album = albums.first(where: { $0.id == id }) else { return nil }
        let mode = EclipseShareProtocol.LibraryMode.resolved(from: album.libraryMode)
        return displayAlbums(for: mode, liveIds: liveIds).first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            albums = try JSONDecoder().decode([LibraryAlbumDTO].self, from: data)
        } catch {
            logger.error("Failed to decode companion albums: \(error.localizedDescription)")
            albums = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(albums)
            defaults.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to encode companion albums: \(error.localizedDescription)")
        }
    }
}
