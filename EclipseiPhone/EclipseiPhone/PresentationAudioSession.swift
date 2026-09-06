//
//  PresentationAudioSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import os

/// Activates the shared presentation `AVAudioSession` for audible program video.
///
/// Needed wherever the app plays unmuted video — the external display, the phone
/// hero in Practice Mode, and fullscreen Preview. Without `.playback`, the app
/// runs on the default `soloAmbient` session, which the Ring/Silent switch
/// silences, so the video looks like it is playing with no sound.
///
/// Calling `setCategory` / `setActive` on every video transition blocks the main
/// thread and can interrupt ambient audio. This helper caches the last applied
/// mode and skips redundant work.
enum PresentationAudioSession {

    private static let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "PresentationAudioSession"
    )

    /// Last mode successfully applied while the session was active.
    private static var activeMode: AVAudioSession.Mode?
    /// True after a successful `setActive(true)` for presentation playback.
    private static var isActivated = false

    /// Ensures `.playback` is active with `AudioAmbientPolicy.presentationAudioMode`.
    ///
    /// No-op when `muted` is true (silent video / screensaver should not grab audio).
    static func activateIfNeeded(muted: Bool) {
        guard !muted else { return }
        let mode = AudioAmbientPolicy.presentationAudioMode
        let session = AVAudioSession.sharedInstance()
        do {
            if activeMode != mode || !isActivated {
                try session.setCategory(.playback, mode: mode)
                activeMode = mode
            }
            if !isActivated {
                try session.setActive(true)
                isActivated = true
            }
        } catch {
            logger.error(
                "Failed to configure presentation audio: \(error.localizedDescription)"
            )
            isActivated = false
            activeMode = nil
        }
    }

    /// Clears the cached activation state (call when the external display disconnects).
    static func reset() {
        isActivated = false
        activeMode = nil
    }
}
