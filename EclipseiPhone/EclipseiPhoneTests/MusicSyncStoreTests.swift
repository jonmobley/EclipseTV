//
//  MusicSyncStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// Applying iCloud songs / playlists to the local stores, and what they send.
@MainActor
struct MusicSyncStoreTests {

    private let early = Date(timeIntervalSince1970: 1_700_000_000)
    private let late = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeDefaults() throws -> UserDefaults {
        let suite = "MusicSync.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeAudioStore() throws -> (AudioStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicSync-\(UUID().uuidString)", isDirectory: true)
        return (AudioStore(defaults: try makeDefaults(), rootDirectory: root), root)
    }

    private func makeAssetFile(bytes: [UInt8] = [1, 2, 3, 4]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-\(UUID().uuidString).mp3")
        try Data(bytes).write(to: url)
        return url
    }

    private func remoteSong(
        id: UUID = UUID(), title: String = "Walk-in", at date: Date
    ) -> SyncedAudioTrack {
        SyncedAudioTrack(
            track: AudioTrack(id: id, title: title, duration: 90, fileExtension: "mp3"),
            modifiedAt: date
        )
    }

    // MARK: - Songs

    @Test func newRemoteSongKeepsItsIdAndFile() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = try makeAssetFile()
        let incoming = remoteSong(at: early)
        #expect(store.applyRemote(incoming, assetURL: asset))
        let id = incoming.track.id
        #expect(store.track(id: id)?.title == "Walk-in")
        let file = try #require(store.fileURL(for: id))
        #expect(file.lastPathComponent == "\(id.uuidString).mp3")
        #expect(store.trackIdsNeedingUpload.isEmpty)
    }

    @Test func newRemoteSongWithoutFileIsNotAdded() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let incoming = remoteSong(at: early)
        #expect(!store.applyRemote(incoming, assetURL: nil))
        #expect(store.track(id: incoming.track.id) == nil)
    }

    @Test func updateWithoutAssetKeepsExistingFile() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        store.applyRemote(remoteSong(id: id, at: early), assetURL: try makeAssetFile())
        #expect(store.applyRemote(remoteSong(id: id, title: "Renamed", at: late), assetURL: nil))
        #expect(store.track(id: id)?.title == "Renamed")
        let file = try #require(store.fileURL(for: id))
        #expect(try Data(contentsOf: file) == Data([1, 2, 3, 4]))
    }

    @Test func olderRemoteSongLosesToLocalEdit() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        store.applyRemote(remoteSong(id: id, at: early), assetURL: try makeAssetFile())
        try store.rename(id: id, to: "Local")
        #expect(store.trackIdsNeedingUpload == [id])
        // The rename is stamped "now", later than `early`.
        #expect(!store.applyRemote(remoteSong(id: id, title: "Stale", at: early), assetURL: nil))
        #expect(store.track(id: id)?.title == "Local")
        #expect(store.syncPayload(for: id)?.track.title == "Local")
        // The file rides along until the server acknowledges the song, then
        // later saves (renames) are metadata only.
        #expect(store.syncAssetURL(for: id) != nil)
        store.markTrackSynced(id: id)
        #expect(store.syncAssetURL(for: id) == nil)
    }

    @Test func protectedSongIsNeitherSentNorOverwritten() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        store.applyRemote(remoteSong(id: id, at: early), assetURL: try makeAssetFile())
        // The bundled-track repair path marks an existing song protected.
        store.ensureBundledTrack(
            id: id, title: "x", resourceName: "none", resourceExtension: "mp3"
        )
        #expect(store.track(id: id)?.isProtected == true)
        #expect(store.syncPayload(for: id) == nil)
        #expect(!store.trackIdsNeedingUpload.contains(id))
        #expect(!store.applyRemote(remoteSong(id: id, title: "Hijack", at: late), assetURL: nil))
        #expect(store.track(id: id)?.title == "Walk-in")
        store.purgeRemote(id: id)
        #expect(store.track(id: id) != nil)
    }

    @Test func bundledSongIdIsIgnoredFromRemote() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let incoming = remoteSong(id: DefaultBackgroundMusic.trackId, at: late)
        #expect(!store.applyRemote(incoming, assetURL: try makeAssetFile()))
    }

    @Test func remoteDeletionRemovesSongAndFile() throws {
        let (store, root) = try makeAudioStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        store.applyRemote(remoteSong(id: id, at: early), assetURL: try makeAssetFile())
        let file = try #require(store.fileURL(for: id))
        store.purgeRemote(id: id)
        #expect(store.track(id: id) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Playlists

    @Test func remotePlaylistKeepsUnknownIdsThroughLocalReorder() throws {
        let store = AudioPlaylistStore(defaults: try makeDefaults())
        let unknown = UUID()
        let (a, b) = (UUID(), UUID())
        let remote = AudioPlaylist(name: "Walk-in", trackIds: [a, unknown, b])
        #expect(store.applyRemote(SyncedAudioPlaylist(playlist: remote, modifiedAt: early)))
        #expect(store.playlist(id: remote.id)?.trackIds == [a, unknown, b])
        // The detail screen only passes songs it can show.
        store.reorder(trackIds: [b, a], inPlaylistId: remote.id)
        #expect(store.playlist(id: remote.id)?.trackIds == [b, unknown, a])
        #expect(store.syncPayload(for: remote.id)?.playlist.trackIds == [b, unknown, a])
        #expect(store.playlistIdsNeedingUpload == [remote.id])
    }

    @Test func playlistTieGoesToRemoteAndOlderLoses() throws {
        let store = AudioPlaylistStore(defaults: try makeDefaults())
        let base = AudioPlaylist(name: "One")
        store.applyRemote(SyncedAudioPlaylist(playlist: base, modifiedAt: early))
        var renamed = base
        renamed.name = "Two"
        #expect(store.applyRemote(SyncedAudioPlaylist(playlist: renamed, modifiedAt: early)))
        #expect(store.playlist(id: base.id)?.name == "Two")
        try store.rename(id: base.id, to: "Local")
        renamed.name = "Stale"
        #expect(!store.applyRemote(SyncedAudioPlaylist(playlist: renamed, modifiedAt: early)))
        #expect(store.playlist(id: base.id)?.name == "Local")
    }

    @Test func protectedPlaylistIsNeitherSentNorOverwritten() throws {
        let store = AudioPlaylistStore(defaults: try makeDefaults())
        let id = DefaultBackgroundMusic.playlistId
        store.ensureProtectedPlaylist(id: id, name: "Background Music", trackIds: [])
        #expect(store.syncPayload(for: id) == nil)
        #expect(store.playlistIdsNeedingUpload.isEmpty)
        let hijack = AudioPlaylist(id: id, name: "Hijack")
        #expect(!store.applyRemote(SyncedAudioPlaylist(playlist: hijack, modifiedAt: late)))
        store.purgeRemote(id: id)
        #expect(store.playlist(id: id)?.name == "Background Music")
    }

    @Test func localPlaylistEditsNeedUploadAndDeletionForgets() throws {
        let store = AudioPlaylistStore(defaults: try makeDefaults())
        let playlist = try store.create(name: "New")
        #expect(store.playlistIdsNeedingUpload == [playlist.id])
        store.markPlaylistSynced(id: playlist.id)
        #expect(store.playlistIdsNeedingUpload.isEmpty)
        store.add(trackId: UUID(), toPlaylistId: playlist.id)
        #expect(store.playlistIdsNeedingUpload == [playlist.id])
        store.delete(id: playlist.id)
        #expect(store.playlist(id: playlist.id) == nil)
        #expect(store.syncLedger.modifiedAt(playlist.id) == nil)
    }
}
