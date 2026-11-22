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
    /// The shipped Eclipse loop does not loop perfectly, so it always blends,
    /// matching the iPhone's Screensaver. Videos sent from a phone keep their
    /// hard, gapless loop.
    ///
    /// - Parameter path: The video's file path
    /// - Returns: `true` for videos shipped inside the app
    static func crossfadesLoop(path: String) -> Bool {
        ShippedVideo.isShipped(path: path)
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
    /// - Parameters:
    ///   - mediaItem: The video to play
    ///   - settings: Its mute and volume settings
    /// - Returns: The player, or `nil` when the video does not blend or its
    ///   blended version is not built yet (the caller then hard-loops it)
    func makeCrossfadeLoopPlayer(
        for mediaItem: MediaItem,
        settings: AppState.VideoSettings
    ) -> AVPlayer? {
        guard Self.crossfadesLoop(path: mediaItem.path),
              let item = CrossfadeLoopComposer.cachedItem(
                for: URL(fileURLWithPath: mediaItem.path)
              ) else { return nil }
        let queuePlayer = AVQueuePlayer()
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = true
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = settings.isMuted
        queuePlayer.volume = settings.volume
        logger.debug("🔄 Cross-faded loop player for: \(mediaItem.fileName)")
        return queuePlayer
    }
}
