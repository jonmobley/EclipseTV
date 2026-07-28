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

    /// Stops ambient audio when `source` is video; no-op otherwise.
    @MainActor
    static func applyYieldIfNeeded(for source: PresentationSource) {
        guard shouldYield(to: source) else { return }
        AudioPlayerController.shared.stop()
    }
}
