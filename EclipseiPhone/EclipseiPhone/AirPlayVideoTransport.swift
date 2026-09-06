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

    /// Resume-from-park seek window. Frame-accurate seeks force decode from the
    /// previous keyframe; a quarter-second tolerance is invisible to an audience.
    static let resumeSeekTolerance = CMTime(seconds: 0.25, preferredTimescale: 600)

    /// Keeps video in `AVPlayerLayer` when a second screen is attached.
    ///
    /// Do not set `allowsExternalPlayback = false`: that can stop the AirPlay
    /// window from painting and makes iOS treat the app as not using the TV.
    /// `usesExternalPlaybackWhileExternalScreenIsActive = false` is what blocks
    /// the system AirPlay Video chrome (transport controls on the TV).
    static func configureLayerOnlyPlayback(on player: AVPlayer) {
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
    }

    /// Local files cannot stall; skip the stall heuristic so playback starts immediately.
    ///
    /// Remote URLs keep AVPlayer's default `automaticallyWaitsToMinimizeStalling`.
    static func configurePlaybackTiming(on player: AVPlayer, url: URL) {
        guard url.isFileURL else { return }
        player.automaticallyWaitsToMinimizeStalling = false
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

    /// Whether the playhead is parked at the end of the item.
    ///
    /// `AVPlayer.play()` at the end of a non-looping item is a no-op, so transport
    /// play has to seek back to the start instead of just resuming.
    static func isAtEnd(currentTime: TimeInterval, duration: TimeInterval) -> Bool {
        guard currentTime.isFinite, duration.isFinite, duration > 0 else { return false }
        return currentTime >= duration - endThreshold
    }

    /// Slack for `isAtEnd` — the last reported time can sit a frame short of duration.
    private static let endThreshold: TimeInterval = 0.05

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

    /// Seek tolerance for resume vs. scrub.
    ///
    /// - Parameter precise: True for user scrubs (frame-accurate); false for resume.
    static func seekTolerance(precise: Bool) -> CMTime {
        precise ? .zero : resumeSeekTolerance
    }

    /// Seeks, then plays or holds a paused frame (`playImmediately(atRate: 0)`).
    ///
    /// - Parameters:
    ///   - player: Player to start.
    ///   - startAt: Absolute seconds to seek before play/pause.
    ///   - autoplay: When false, parks on a decoded frame.
    ///   - url: Media URL — local files use `playImmediately` and skip stall waits.
    ///   - preciseSeek: Frame-accurate seek (scrubs); resume uses a modest tolerance.
    ///   - completion: Invoked on the main queue after seek + play/pause.
    static func start(
        _ player: AVPlayer,
        at startAt: TimeInterval,
        autoplay: Bool,
        url: URL? = nil,
        preciseSeek: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let isLocal = url?.isFileURL ?? false
        let go = {
            if autoplay {
                if isLocal {
                    player.playImmediately(atRate: 1)
                } else {
                    player.play()
                }
            } else {
                player.pause()
                player.playImmediately(atRate: 0)
            }
            completion?()
        }
        if startAt > 0 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            let tolerance = seekTolerance(precise: preciseSeek)
            player.seek(
                to: time,
                toleranceBefore: tolerance,
                toleranceAfter: tolerance
            ) { _ in
                go()
            }
        } else {
            go()
        }
    }
}
