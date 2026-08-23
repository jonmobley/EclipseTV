//
//  AirPlayVideoTransport.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation

/// Timing and identity helpers for the AirPlay library-video player.
///
/// Transport chrome stays on the phone. The external display is `AVPlayerLayer`
/// only — never `AVPlayerViewController` or on-screen controls.
enum AirPlayVideoTransport {

    /// Keeps video in `AVPlayerLayer` when a second screen is attached.
    ///
    /// Do not set `allowsExternalPlayback = false`: that can stop the AirPlay
    /// window from painting and makes iOS treat the app as not using the TV.
    /// `usesExternalPlaybackWhileExternalScreenIsActive = false` is what blocks
    /// the system AirPlay Video chrome (transport controls on the TV).
    static func configureLayerOnlyPlayback(on player: AVPlayer) {
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
    }

    /// Whether `url` is the file for `itemId` (local path or id in the name).
    static func url(_ url: URL, matchesItemId itemId: String, localURL: URL?) -> Bool {
        if let localURL, localURL.standardizedFileURL == url.standardizedFileURL {
            return true
        }
        return url.lastPathComponent == itemId
            || url.deletingPathExtension().lastPathComponent == itemId
    }

    /// Clamps a seek/skip target into `[0, duration]` when duration is known.
    static func clampedTime(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        var target = max(0, time)
        if duration.isFinite, duration > 0 {
            target = min(target, duration)
        }
        return target
    }

    /// Phone-hero `PlaybackState` from an AirPlay player snapshot.
    static func playbackState(
        itemId: String?,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> PlaybackState {
        PlaybackState(
            itemId: itemId,
            isPlaying: isPlaying,
            currentTime: currentTime.isFinite ? max(0, currentTime) : 0,
            duration: duration.isFinite ? max(0, duration) : 0
        )
    }

    /// Time to restore after a temporary blank, or `fallback` when the player has none.
    static func parkedStartTime(player: AVPlayer?, fallback: TimeInterval) -> TimeInterval {
        guard let player else { return fallback }
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, seconds > 0 else { return fallback }
        return seconds
    }

    /// Seeks, then plays or holds a paused frame (`playImmediately(atRate: 0)`).
    static func start(
        _ player: AVPlayer,
        at startAt: TimeInterval,
        autoplay: Bool,
        completion: (() -> Void)? = nil
    ) {
        let go = {
            if autoplay {
                player.play()
            } else {
                player.pause()
                player.playImmediately(atRate: 0)
            }
            completion?()
        }
        if startAt > 0 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                go()
            }
        } else {
            go()
        }
    }
}
