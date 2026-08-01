//
//  DefaultBackgroundMusicTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct DefaultBackgroundMusicTests {

    @Test func protectedPlaylistCannotBeDeletedOrRenamed() throws {
        let suite = "DefaultBackgroundMusicTests.playlist.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = AudioPlaylistStore(defaults: defaults)

        store.ensureProtectedPlaylist(
            id: DefaultBackgroundMusic.playlistId,
            name: DefaultBackgroundMusic.playlistName,
            trackIds: [DefaultBackgroundMusic.trackId]
        )
        #expect(store.playlist(id: DefaultBackgroundMusic.playlistId)?.isProtected == true)

        store.delete(id: DefaultBackgroundMusic.playlistId)
        #expect(store.playlist(id: DefaultBackgroundMusic.playlistId) != nil)

        try store.rename(id: DefaultBackgroundMusic.playlistId, to: "Other")
        #expect(
            store.playlist(id: DefaultBackgroundMusic.playlistId)?.name
                == DefaultBackgroundMusic.playlistName
        )
    }

    @Test func protectedTrackCannotLeaveProtectedPlaylist() {
        let suite = "DefaultBackgroundMusicTests.membership.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Seed the shared track store so membership checks see isProtected.
        DefaultBackgroundMusic.ensureSeeded()
        let playlistStore = AudioPlaylistStore(defaults: defaults)
        playlistStore.ensureProtectedPlaylist(
            id: DefaultBackgroundMusic.playlistId,
            name: DefaultBackgroundMusic.playlistName,
            trackIds: [DefaultBackgroundMusic.trackId]
        )

        playlistStore.remove(
            trackId: DefaultBackgroundMusic.trackId,
            fromPlaylistId: DefaultBackgroundMusic.playlistId
        )
        #expect(
            playlistStore.playlist(id: DefaultBackgroundMusic.playlistId)?
                .trackIds.contains(DefaultBackgroundMusic.trackId) == true
        )
    }

    @Test func ensureSeededCreatesProtectedTrackAndPlaylist() {
        DefaultBackgroundMusic.ensureSeeded()
        let track = AudioStore.shared.track(id: DefaultBackgroundMusic.trackId)
        #expect(track?.isProtected == true)
        #expect(track?.title == DefaultBackgroundMusic.trackTitle)
        #expect(AudioStore.shared.fileURL(for: DefaultBackgroundMusic.trackId) != nil)

        let playlist = AudioPlaylistStore.shared.playlist(
            id: DefaultBackgroundMusic.playlistId
        )
        #expect(playlist?.isProtected == true)
        #expect(playlist?.name == DefaultBackgroundMusic.playlistName)
        #expect(playlist?.trackIds.contains(DefaultBackgroundMusic.trackId) == true)
    }

    @Test func preparePlaylistArmsWithoutPlaying() {
        DefaultBackgroundMusic.ensureSeeded()
        guard let playlist = AudioPlaylistStore.shared.playlist(
            id: DefaultBackgroundMusic.playlistId
        ) else {
            Issue.record("Missing Background Music playlist")
            return
        }
        AudioPlayerController.shared.stop()
        AudioPlayerController.shared.preparePlaylist(
            playlist,
            startingAt: DefaultBackgroundMusic.trackId
        )
        #expect(AudioPlayerController.shared.hasActiveSession)
        #expect(AudioPlayerController.shared.isPlaying == false)
        #expect(
            AudioPlayerController.shared.currentTrack?.id
                == DefaultBackgroundMusic.trackId
        )
        AudioPlayerController.shared.stop()
    }
}
