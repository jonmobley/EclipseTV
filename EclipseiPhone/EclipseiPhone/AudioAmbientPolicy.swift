//
//  AudioAmbientPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Rules for when ambient music yields to (or coexists with) presentation content.
enum AudioAmbientPolicy {

    /// Whether starting `source` should stop ambient audio.
    static func shouldYield(to source: PresentationSource) -> Bool {
        switch source.content {
        case .video:
            return true
        case .image, .camera, .web, .pdf, .black, .unavailable:
            return false
        }
    }

    /// Pauses ambient audio when `source` is video; no-op otherwise.
    ///
    /// Pauses rather than stops: `stop()` clears the queue and hides the mini player, so
    /// playing one video would cost the user their whole ambient session.
    @MainActor
    static func applyYieldIfNeeded(for source: PresentationSource) {
        guard shouldYield(to: source) else { return }
        AudioPlayerController.shared.pause()
    }
}
