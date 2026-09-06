//
//  AudioAmbientPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation

/// Rules for when ambient music yields to (or coexists with) presentation content.
enum AudioAmbientPolicy {

    /// Whether starting `source` should pause ambient audio.
    ///
    /// Off by default (`pauseMusicForVideo`): music keeps playing under video. When the
    /// setting is on, unmuted library video still pauses rather than stops.
    static func shouldYield(to source: PresentationSource) -> Bool {
        guard ExternalOutputSettings.pauseMusicForVideo else { return false }
        switch source.content {
        case .video(_, _, let isMuted):
            // Muted library video can sit under Background Music; audible video cannot.
            return !isMuted
        case .webVideo:
            // YouTube / Vimeo embeds are audible by default.
            return true
        case .image, .screensaver, .camera, .web, .pdf, .black, .countdown, .unavailable:
            // Web yields later, when HTML5 media actually plays unmuted.
            return false
        }
    }

    /// Whether a phone-browser media event means audible content is playing.
    static func shouldYield(toWebMedia event: EclipseWebMediaSync.Event) -> Bool {
        guard ExternalOutputSettings.pauseMusicForVideo else { return false }
        guard !event.muted, !event.paused else { return false }
        switch event.action {
        case "play", "timeupdate", "seeked", "volumechange", "ratechange":
            return true
        default:
            return false
        }
    }

    /// `.moviePlayback` ducks other audio; use it only when music is supposed to yield.
    static var presentationAudioMode: AVAudioSession.Mode {
        ExternalOutputSettings.pauseMusicForVideo ? .moviePlayback : .default
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

    /// Pauses ambient audio when a YouTube / Vimeo embed is playing unmuted.
    @MainActor
    static func applyYieldIfNeeded(forWebVideoPlaying playing: Bool, muted: Bool) {
        guard ExternalOutputSettings.pauseMusicForVideo else { return }
        guard playing, !muted else { return }
        AudioPlayerController.shared.pause()
    }
}
