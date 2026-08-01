//
//  AudioPlayerController+Fade.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Volume Fade

extension AudioPlayerController {

    /// Duration for transport fade-in / fade-out.
    static let volumeFadeDuration: TimeInterval = 0.55

    /// Cancels any in-flight volume ramp.
    func cancelVolumeFade() {
        volumeFadeTask?.cancel()
        volumeFadeTask = nil
    }

    /// Ramps `player.volume` to `target`, then runs `completion` on the main actor.
    func fadePlayerVolume(to target: Float, then completion: (() -> Void)? = nil) {
        cancelVolumeFade()
        guard let player else {
            completion?()
            return
        }
        let start = player.volume
        if abs(start - target) < 0.01 {
            player.volume = target
            completion?()
            return
        }

        let duration = Self.volumeFadeDuration
        let steps = 28
        volumeFadeTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                let ns = UInt64(duration / Double(steps) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard let self, !Task.isCancelled else { return }
                guard let player = self.player else { return }
                let t = Float(step) / Float(steps)
                player.volume = start + (target - start) * t
            }
            guard let self, !Task.isCancelled else { return }
            self.player?.volume = target
            self.volumeFadeTask = nil
            completion?()
        }
    }
}
