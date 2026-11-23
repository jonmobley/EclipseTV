//
//  ImageViewController+CrossfadeLoop.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation

// MARK: - Cross-Faded Loop

extension ImageViewController {

    /// Whether a looping video blends its end into its start.
    ///
    /// Follows the video's Cross-Fade Loop setting (set from the phone). With no
    /// setting, only the shipped Eclipse loop blends, matching the iPhone's
    /// Screensaver; other videos keep a hard, gapless loop.
    ///
    /// - Parameters:
    ///   - path: The video's file path
    ///   - settings: Its stored settings
    /// - Returns: `true` when the loop point should dissolve
    nonisolated static func crossfadesLoop(path: String, settings: AppState.VideoSettings) -> Bool {
        settings.crossfadesLoop ?? ShippedVideo.isShipped(path: path)
    }

    /// Builds the blended versions of the shipped loops at launch so they
    /// play without delay when chosen (a few milliseconds per clip).
    func prepareShippedCrossfadeLoops() {
        let urls = ShippedVideo.bundledURLs
        Task { @MainActor in
            for url in urls {
                await CrossfadeLoopComposer.prepare(url)
            }
        }
    }

    /// A looping player that plays the blended version of `mediaItem`.
    ///
    /// When the blend is wanted but not built yet, starts building it and
    /// returns `nil` (the caller hard-loops); once built, the player is rebuilt
    /// in place if the same video is still on screen.
    ///
    /// - Parameters:
    ///   - mediaItem: The video to play
    ///   - settings: Its mute, volume and cross-fade settings
    /// - Returns: The blended player, or `nil` to hard-loop
    func makeCrossfadeLoopPlayer(
        for mediaItem: MediaItem,
        settings: AppState.VideoSettings
    ) -> AVPlayer? {
        guard Self.crossfadesLoop(path: mediaItem.path, settings: settings) else { return nil }
        let url = URL(fileURLWithPath: mediaItem.path)
        guard CrossfadeLoopComposer.isPrepared(url) else {
            buildCrossfadeThenApply(url: url)
            return nil
        }
        guard let item = CrossfadeLoopComposer.cachedItem(for: url) else { return nil }
        let queuePlayer = AVQueuePlayer()
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = true
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = settings.isMuted
        queuePlayer.volume = settings.volume
        logger.debug("🔄 Cross-faded loop player for: \(mediaItem.fileName)")
        return queuePlayer
    }

    // MARK: - Private Helpers

    /// Builds the blend, then switches the on-screen video to it if still shown.
    private func buildCrossfadeThenApply(url: URL) {
        Task { @MainActor [weak self] in
            await CrossfadeLoopComposer.prepare(url)
            guard let self, self.currentDisplayPath() == url.path else { return }
            self.applySettingsToCurrentVideo()
        }
    }
}
