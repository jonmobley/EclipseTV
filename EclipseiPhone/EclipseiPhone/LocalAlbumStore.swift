//
//  LocalAlbumStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists user-created local albums as JSON metadata in UserDefaults.
@MainActor
final class LocalAlbumStore {

    static let shared = LocalAlbumStore()

    /// Posted when the albums list or membership changes.
    static let didChangeNotification = Notification.Name("LocalAlbumStore.didChange")

    enum StoreError: LocalizedError {
        case emptyName

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter a name for the Show."
            }
        }
    }

    private(set) var albums: [LocalAlbum] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.localAlbums.items"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LocalAlbumStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    /// Albums that belong to the active Display Mode.
    var albumsForCurrentMode: [LocalAlbum] {
        let mode = ExternalOutputSettings.orientation
        return albums.filter { $0.orientation == mode }
    }

    /// Every album for cross-mode pickers: active Display Mode first, then the other.
    var albumsActiveModeFirst: [LocalAlbum] {
        let mode = ExternalOutputSettings.orientation
        return albums.filter { $0.orientation == mode }
            + albums.filter { $0.orientation != mode }
    }

    /// Creates an empty album in `orientation` and inserts it at the front.
    @discardableResult
    func create(
        name: String,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation
    ) throws -> LocalAlbum {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        let album = LocalAlbum(name: trimmed, orientation: orientation)
        albums.insert(album, at: 0)
        persist()
        return album
    }

    /// Renames the album with `id` when present.
    func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        albums[index].name = trimmed
        persist()
    }

    /// Deletes the album with `id` when present.
    func delete(id: UUID) {
        let before = albums.count
        albums.removeAll { $0.id == id }
        guard albums.count != before else { return }
        persist()
    }

    /// Moves `id` to the front so it leads the Recent Shows ribbon.
    func touchRecentlyOpened(id: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let album = albums.remove(at: index)
        albums.insert(album, at: 0)
        persist()
    }

    /// Appends `itemId` to the album if it is not already a member.
    func add(itemId: String, toAlbumId albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard !albums[index].itemIds.contains(itemId) else { return }
        albums[index].itemIds.append(itemId)
        if albums[index].coverId == nil {
            albums[index].coverId = itemId
        }
        persist()
    }

    /// Removes `itemId` from the album when present.
    func remove(itemId: String, fromAlbumId albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        albums[index].itemIds.removeAll { $0 == itemId }
        if albums[index].coverId == itemId {
            albums[index].coverId = albums[index].itemIds.first
        }
        persist()
    }

    /// Replaces the album's ordered membership.
    func reorder(itemIds: [String], inAlbumId albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        albums[index].itemIds = itemIds
        if let cover = albums[index].coverId, !itemIds.contains(cover) {
            albums[index].coverId = itemIds.first
        }
        persist()
    }

    /// Sets the cover thumbnail for `albumId` when `itemId` is a member.
    func setCover(itemId: String, albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard albums[index].itemIds.contains(itemId) else { return }
        guard albums[index].coverId != itemId else { return }
        albums[index].coverId = itemId
        persist()
    }

    /// Drops `itemId` from every album (e.g. after library delete).
    func removeItemFromAllAlbums(itemId: String) {
        var changed = false
        for index in albums.indices {
            let before = albums[index].itemIds.count
            albums[index].itemIds.removeAll { $0 == itemId }
            guard albums[index].itemIds.count != before else { continue }
            changed = true
            if albums[index].coverId == itemId {
                albums[index].coverId = albums[index].itemIds.first
            }
        }
        if changed { persist() }
    }

    /// Removes membership ids that are no longer in the library.
    func pruneMissingItems(keeping validIds: Set<String>) {
        var changed = false
        for index in albums.indices {
            let before = albums[index].itemIds
            let after = before.filter { validIds.contains($0) }
            guard after != before else { continue }
            albums[index].itemIds = after
            changed = true
            if let cover = albums[index].coverId, !after.contains(cover) {
                albums[index].coverId = after.first
            }
        }
        if changed { persist() }
    }

    /// Album with `id`, if any.
    func album(id: UUID) -> LocalAlbum? {
        albums.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: itemsKey) else { return }
        do {
            albums = try JSONDecoder().decode([LocalAlbum].self, from: data)
        } catch {
            logger.error("Failed to decode local albums: \(error.localizedDescription)")
            albums = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(albums)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode local albums: \(error.localizedDescription)")
        }
    }
}
