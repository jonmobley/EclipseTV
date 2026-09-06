//
//  PresentationPrewarmer.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation

/// Single-slot prewarmer for the next likely AirPlay library video.
///
/// Creates an `AVPlayerItem` and loads essential properties off the main thread so
/// `installIncomingVideo` can skip cold asset setup when the URL matches. Cap of
/// one item mirrors `WarmWebSessionPool` discipline — never accumulate players.
@MainActor
final class PresentationPrewarmer {

    /// Shared slot used by the grid and `PresentationViewController`.
    static let shared = PresentationPrewarmer()

    private var url: URL?
    private var item: AVPlayerItem?
    private var loadTask: Task<Void, Never>?

    private init() {}

    /// Begins preparing `url` for playback. Replaces any previous slot.
    ///
    /// - Parameter url: Local or remote video URL expected to present next.
    func prewarm(url: URL) {
        let standardized = url.standardizedFileURL
        if self.url == standardized, item != nil { return }
        clear()
        self.url = standardized
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        item = playerItem
        loadTask = Task { [weak self] in
            _ = try? await asset.load(.isPlayable, .tracks, .duration)
            guard !Task.isCancelled else { return }
            // Keep the item warm; status becomes readyToPlay as AVFoundation buffers.
            _ = self?.item
        }
    }

    /// Returns and clears the prewarmed item when it matches `url`.
    ///
    /// - Parameter url: URL about to be presented.
    /// - Returns: A prepared `AVPlayerItem`, or nil on miss / empty slot.
    func takeItem(matching url: URL) -> AVPlayerItem? {
        let standardized = url.standardizedFileURL
        guard self.url == standardized, let item else { return nil }
        loadTask?.cancel()
        loadTask = nil
        self.url = nil
        self.item = nil
        return item
    }

    /// Drops the slot without consuming it (other content is presenting).
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        url = nil
        item = nil
    }

    /// Whether a slot is held for `url` (tests / diagnostics).
    func isPrepared(for url: URL) -> Bool {
        self.url == url.standardizedFileURL && item != nil
    }
}
