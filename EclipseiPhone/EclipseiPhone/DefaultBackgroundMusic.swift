//
//  DefaultBackgroundMusic.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Bundled Background Music playlist + Chill Low Fi seed for every install.
enum DefaultBackgroundMusic {

    /// Stable playlist id across installs / reinstalls of metadata.
    static let playlistId = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
    /// Stable track id for the bundled Chill Low Fi file.
    static let trackId = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!

    static let playlistName = "Background Music"
    static let trackTitle = "Chill Low Fi"
    static let bundledResourceName = "ChillLowFi"
    static let bundledResourceExtension = "mp3"

    private static let armedKey = "EclipseTV.audio.didArmDefaultOnFirstLaunch"

    /// Ensures the protected playlist and track exist on disk and in stores.
    @MainActor
    static func ensureSeeded() {
        AudioStore.shared.ensureBundledTrack(
            id: trackId,
            title: trackTitle,
            resourceName: bundledResourceName,
            resourceExtension: bundledResourceExtension
        )
        AudioPlaylistStore.shared.ensureProtectedPlaylist(
            id: playlistId,
            name: playlistName,
            trackIds: [trackId]
        )
    }

    /// On first launch only: load Background Music paused into the mini player.
    @MainActor
    static func armOnFirstLaunchIfNeeded() {
        ensureSeeded()
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: armedKey) else { return }
        guard let playlist = AudioPlaylistStore.shared.playlist(id: playlistId)
        else { return }
        AudioPlayerController.shared.preparePlaylist(playlist, startingAt: trackId)
        defaults.set(true, forKey: armedKey)
    }
}
