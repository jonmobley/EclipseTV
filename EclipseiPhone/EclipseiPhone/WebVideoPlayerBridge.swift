//
//  WebVideoPlayerBridge.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import WebKit

/// Bridges YouTube / Vimeo embed player events from the AirPlay WebView to native.
///
/// Modeled on `EclipseWebMediaSync`, but talks to the provider player object
/// (`window.__eclipseWebVideo`) instead of an HTML5 `<video>` element.
enum WebVideoPlayerBridge {

    static let messageName = "eclipseWebVideo"

    /// Play / pause / seek payload posted by the shell's reporter.
    struct Event: Equatable {
        var action: String
        var currentTime: Double
        var duration: Double
        var paused: Bool
        var muted: Bool

        init?(messageBody: Any) {
            guard let dict = messageBody as? [String: Any] else { return nil }
            action = (dict["action"] as? String) ?? ""
            guard !action.isEmpty else { return nil }
            currentTime = dict["currentTime"] as? Double ?? 0
            duration = dict["duration"] as? Double ?? 0
            paused = dict["paused"] as? Bool ?? true
            muted = dict["muted"] as? Bool ?? false
        }

        /// Snapshot for the phone hero scrubber.
        var playbackState: PlaybackState {
            PlaybackState(
                itemId: nil,
                isPlaying: !paused && action != "ended",
                currentTime: currentTime.isFinite ? max(0, currentTime) : 0,
                duration: duration.isFinite ? max(0, duration) : 0
            )
        }
    }

    /// JS that invokes `window.__eclipseWebVideo.play()`.
    static let playJavaScript = "window.__eclipseWebVideo && window.__eclipseWebVideo.play();"

    /// JS that invokes `window.__eclipseWebVideo.pause()`.
    static let pauseJavaScript = "window.__eclipseWebVideo && window.__eclipseWebVideo.pause();"

    /// JS that seeks the embed player to `seconds`.
    static func seekJavaScript(to seconds: TimeInterval) -> String {
        let t = seconds.isFinite ? max(0, seconds) : 0
        return "window.__eclipseWebVideo && window.__eclipseWebVideo.seek(\(t));"
    }

    /// JS that mutes or unmutes the embed player.
    static func muteJavaScript(_ muted: Bool) -> String {
        "window.__eclipseWebVideo && window.__eclipseWebVideo.mute(\(muted ? "true" : "false"));"
    }
}
