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
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        let playlist = AudioPlaylist(name: trimmed)
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    /// Renames the playlist with `id` when present. Protected playlists are ignored.
    func rename(id: UUID, to name: String) throws {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        guard !playlists[index].isProtected else { return }
        playlists[index].name = trimmed
        persist()
    }

    /// Deletes the playlist with `id` when present. Protected playlists are ignored.
    func delete(id: UUID) {
        guard let existing = playlists.first(where: { $0.id == id }),
              !existing.isProtected else { return }
        let before = playlists.count
        playlists.removeAll { $0.id == id }
        guard playlists.count != before else { return }
        if lastPlayedPlaylistId == id {
            lastPlayedPlaylistId = nil
        }
        persist()
    }

    /// Inserts or repairs a protected system playlist and ensures membership.
    func ensureProtectedPlaylist(id: UUID, name: String, trackIds: [UUID]) {
        if let index = playlists.firstIndex(where: { $0.id == id }) {
            var playlist = playlists[index]
            var changed = false
            if !playlist.isProtected {
                playlist.isProtected = true
                changed = true
            }
            if playlist.name != name {
                playlist.name = name
                changed = true
            }
            for trackId in trackIds where !playlist.trackIds.contains(trackId) {
                playlist.trackIds.insert(trackId, at: 0)
                changed = true
            }
            if changed {
                playlists[index] = playlist
                persist()
            }
            return
        }
        let playlist = AudioPlaylist(
            id: id,
            name: name,
            trackIds: trackIds,
            isProtected: true
        )
        playlists.insert(playlist, at: 0)
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
    /// Protected tracks cannot leave a protected playlist.
    func remove(trackId: UUID, fromPlaylistId playlistId: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else {
            return
        }
        let playlist = playlists[index]
        if playlist.isProtected,
           let track = AudioStore.shared.track(id: trackId),
           track.isProtected {
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

    /// Drops `trackId` from every playlist (skips protected membership).
    func removeTrackFromAllPlaylists(trackId: UUID) {
        let trackProtected = AudioStore.shared.track(id: trackId)?.isProtected == true
        var changed = false
        for index in playlists.indices {
            if playlists[index].isProtected && trackProtected { continue }
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
        playlists = SalvagingListDecoder.decodeList(
            AudioPlaylist.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
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
