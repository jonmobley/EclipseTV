//
//  PresentationViewController+CrossfadeLoop.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation

// MARK: - Cross-Faded Loop

extension PresentationViewController {

    /// The blended (Cross-Fade Loop) item for a looping video, when built.
    ///
    /// Blends are built ahead of time when the option is turned on and whenever
    /// the library changes. If one is still missing, building starts now and this
    /// playback hard-loops; the next presentation of the video blends.
    ///
    /// - Parameter url: Local video file URL
    /// - Returns: A fresh blended item, or `nil` to play the plain file
    func crossfadeLoopItem(for url: URL) -> AVPlayerItem? {
        guard url.isFileURL else { return nil }
        if !CrossfadeLoopComposer.isPrepared(url) {
            Task { @MainActor in await CrossfadeLoopComposer.prepare(url) }
            return nil
        }
        return CrossfadeLoopComposer.cachedItem(for: url)
    }
}
