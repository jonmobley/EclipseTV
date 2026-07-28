//
//  AudioPlaylistStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists user-created audio playlists as JSON metadata in UserDefaults.
@MainActor
final class AudioPlaylistStore {

    static let shared = AudioPlaylistStore()

    /// Posted when playlists change.
    static let didChangeNotification = Notification.Name("AudioPlaylistStore.didChange")

    enum StoreError: LocalizedError {
        case emptyName

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter a name for the playlist."
            }
        }
    }

    private(set) var playlists: [AudioPlaylist] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.audioPlaylists.items"
    private let lastPlaylistKey = "EclipseTV.audioPlaylists.lastId"
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios", category: "AudioPlaylistStore"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    /// Creates an empty playlist and inserts it at the front.
    @discardableResult
    func create(name: String) throws -> AudioPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        let playlist = AudioPlaylist(name: trimmed)
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    /// Renames the playlist with `id` when present.
    func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = trimmed
        persist()
    }

    /// Deletes the playlist with `id` when present.
    func delete(id: UUID) {
        let before = playlists.count
        playlists.removeAll { $0.id == id }
        guard playlists.count != before else { return }
        if lastPlayedPlaylistId == id {
            lastPlayedPlaylistId = nil
        }
        persist()
    }

    /// Appends `trackId` when not already a member.
    func add(trackId: UUID, toPlaylistId playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else {
            return
        }
        guard !playlists[index].trackIds.contains(trackId) else { return }
        playlists[index].trackIds.append(trackId)
        persist()
    }

    /// Removes `trackId` from the playlist when present.
    func remove(trackId: UUID, fromPlaylistId playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else {
            return
        }
        playlists[index].trackIds.removeAll { $0 == trackId }
        persist()
    }

    /// Replaces the playlist's ordered membership.
    func reorder(trackIds: [UUID], inPlaylistId playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else {
            return
        }
        playlists[index].trackIds = trackIds
        persist()
    }

    /// Drops `trackId` from every playlist.
    func removeTrackFromAllPlaylists(trackId: UUID) {
        var changed = false
        for index in playlists.indices {
            let before = playlists[index].trackIds.count
            playlists[index].trackIds.removeAll { $0 == trackId }
            if playlists[index].trackIds.count != before { changed = true }
        }
        if changed { persist() }
    }

    /// Playlist with `id`, if any.
    func playlist(id: UUID) -> AudioPlaylist? {
        playlists.first { $0.id == id }
    }

    /// Last playlist the user played, if still present.
    var lastPlayedPlaylistId: UUID? {
        get {
            guard let raw = defaults.string(forKey: lastPlaylistKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: lastPlaylistKey)
            } else {
                defaults.removeObject(forKey: lastPlaylistKey)
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: itemsKey) else { return }
        do {
            playlists = try JSONDecoder().decode([AudioPlaylist].self, from: data)
        } catch {
            logger.error("Failed to decode playlists: \(error.localizedDescription)")
            playlists = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(playlists)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode playlists: \(error.localizedDescription)")
        }
    }
}
