//
//  AudioAmbientPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Rules for when ambient music yields to (or coexists with) presentation content.
enum AudioAmbientPolicy {

    /// Whether starting `source` should pause ambient audio.
    static func shouldYield(to source: PresentationSource) -> Bool {
        switch source.content {
        case .video(_, _, let isMuted):
            // Muted library video can sit under Background Music; audible video cannot.
            return !isMuted
        case .image, .screensaver, .camera, .web, .pdf, .black, .countdown, .unavailable:
            // Web yields later, when HTML5 media actually plays unmuted.
            return false
        }
    }

    /// Whether a phone-browser media event means audible content is playing.
    static func shouldYield(toWebMedia event: EclipseWebMediaSync.Event) -> Bool {
        guard !event.muted, !event.paused else { return false }
        switch event.action {
        case "play", "timeupdate", "seeked", "volumechange", "ratechange":
            return true
        default:
            return false
        }
    }

    /// Pauses ambient audio when `source` is audible video; no-op otherwise.
    ///
    /// Pauses rather than stops: `stop()` clears the queue and hides the mini player, so
    /// playing one video would cost the user their whole ambient session.
    @MainActor
    static func applyYieldIfNeeded(for source: PresentationSource) {
        guard shouldYield(to: source) else { return }
        AudioPlayerController.shared.pause()
    }

    /// Pauses ambient audio when a website plays unmuted HTML5 media.
    @MainActor
    static func applyYieldIfNeeded(forWebMedia event: EclipseWebMediaSync.Event) {
        guard shouldYield(toWebMedia: event) else { return }
        AudioPlayerController.shared.pause()
    }
}
