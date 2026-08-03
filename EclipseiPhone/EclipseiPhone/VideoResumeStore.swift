//
//  VideoResumeStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Remembers mid-playback leave state for library videos: resume position + parked frame.
///
/// Tap resumes from the parked time; the tile **Rewind** control clears this without
/// going live. Session-scoped (not persisted across launches).
@MainActor
final class VideoResumeStore {

    static let shared = VideoResumeStore()

    /// Posted when a resume entry is added, updated, or cleared.
    static let didChangeNotification = Notification.Name("VideoResumeStore.didChange")

    /// Ignore tiny scrub / accidental leaves.
    private static let minimumResumeSeconds: TimeInterval = 1
    /// Leaving in the final second counts as finished — no resume chip.
    private static let endGraceSeconds: TimeInterval = 1

    private struct Entry {
        let itemId: String
        var position: TimeInterval
        var frame: UIImage?
    }

    private var entries: [String: Entry] = [:]
    private var frameGeneration: [String: Int] = [:]

    private init() {}

    // MARK: - Queries

    /// Absolute seconds to resume from, when a mid-play leave was parked.
    func position(for itemId: String) -> TimeInterval? {
        guard let entry = entries[itemId], entry.position >= Self.minimumResumeSeconds else {
            return nil
        }
        return entry.position
    }

    /// Last-frame art for the tile while a resume point exists.
    func frame(for itemId: String) -> UIImage? {
        entries[itemId]?.frame
    }

    /// Whether the tile should show the non-live Rewind control.
    func hasResume(for itemId: String) -> Bool {
        position(for: itemId) != nil
    }

    // MARK: - Mutations

    /// Drops a saved resume point (Rewind, or starting playback from that item).
    func clear(for itemId: String) {
        guard entries.removeValue(forKey: itemId) != nil else { return }
        frameGeneration[itemId, default: 0] += 1
        notifyChanged(itemId: itemId)
    }

    /// Parks leave state when the user navigates away mid-playback.
    ///
    /// No-ops when position can't be read or is too near the start/end — so a second
    /// hook after the player is already torn down won't wipe a good park with zeros.
    func parkLeavingVideoIfNeeded(itemId: String?) {
        guard let itemId,
              let item = TVLibraryStore.shared.items.first(where: { $0.id == itemId }),
              item.isVideo
        else { return }

        guard let position = Self.capturePosition(for: itemId) else { return }
        if position < Self.minimumResumeSeconds {
            return
        }
        let duration = item.duration > 0
            ? item.duration
            : (TVLibraryStore.shared.playback.itemId == itemId
                ? TVLibraryStore.shared.playback.duration
                : 0)
        if duration > 0, position >= duration - Self.endGraceSeconds {
            clear(for: itemId)
            return
        }

        var entry = entries[itemId] ?? Entry(itemId: itemId, position: position, frame: nil)
        entry.position = position
        entries[itemId] = entry
        notifyChanged(itemId: itemId)
        generateFrame(for: itemId, at: position)
    }

    // MARK: - Position / Frame

    /// Prefers the live AirPlay player; falls back to Multipeer `PlaybackState`.
    private static func capturePosition(for itemId: String) -> TimeInterval? {
        if let airPlay = ExternalDisplayManager.shared.currentVideoPlaybackTime(
            forItemId: itemId
        ) {
            return airPlay
        }
        let playback = TVLibraryStore.shared.playback
        guard playback.itemId == itemId, playback.currentTime > 0 else { return nil }
        return playback.currentTime
    }

    private func generateFrame(for itemId: String, at position: TimeInterval) {
        guard let url = LocalMediaStore.shared.localURL(forId: itemId) else { return }
        let generation = (frameGeneration[itemId] ?? 0) + 1
        frameGeneration[itemId] = generation

        Task.detached(priority: .utility) { [weak self] in
            let image = Self.previewFrame(at: url, seconds: position)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.frameGeneration[itemId] == generation,
                      var entry = self.entries[itemId]
                else { return }
                entry.frame = image
                self.entries[itemId] = entry
                self.notifyChanged(itemId: itemId)
            }
        }
    }

    nonisolated private static func previewFrame(at url: URL, seconds: TimeInterval) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let semaphore = DispatchSemaphore(value: 0)
        var image: UIImage?
        Task {
            defer { semaphore.signal() }
            do {
                let cg = try await generator.image(at: time).image
                image = UIImage(cgImage: cg)
            } catch {
                image = nil
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return image
    }

    private func notifyChanged(itemId: String) {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: ["itemId": itemId]
        )
    }
}
