//
//  VideoPosterFrame.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import CoreImage
import UIKit

/// Picks a grid poster from a local video, skipping black encoder lead-in frames.
enum VideoPosterFrame {
    static let maximumSize = CGSize(width: 720, height: 720)

    /// Later sample points for long videos. Films and recorded shows often open
    /// on many seconds of black or dark titles, so the first 3 s alone left the
    /// card on the film placeholder (a 1 h 28 min movie synced from the Mac).
    private static let laterSeconds: [TimeInterval] = [5, 10, 30]
    private static let laterFractions: [Double] = [0.1, 0.25]

    /// Times to try, in order. First frame is preferred when it isn’t black.
    static func candidateSeconds(duration: TimeInterval) -> [TimeInterval] {
        let end = duration.isFinite ? max(duration, 0) : 0
        if end < 0.35 {
            return uniqued(
                [end * 0.5, end * 0.75, 0].map { clamp($0, duration: end) }
            )
        }
        var points: [TimeInterval] = [0, 0.2, 0.5, 1.0, 2.0, min(3.0, end * 0.45)]
        points += laterSeconds.filter { $0 < end * 0.5 }
        points += laterFractions.map { end * $0 }.filter { $0 > 3.0 }
        return uniqued(points.map { clamp($0, duration: end) })
    }

    /// True when a still is visible enough to use as a library thumbnail.
    static func isUsable(_ image: UIImage) -> Bool {
        !isNearlyBlack(image)
    }

    /// Duration of the file in seconds, or 0 when the asset cannot be read.
    static func durationSeconds(at url: URL) async -> TimeInterval {
        await assetDurationSeconds(AVURLAsset(url: url))
    }

    /// Best non-black still from `url`. Nil when every sampled frame is empty.
    ///
    /// Async on purpose: the old blocking version parked a thumbnail-queue thread for
    /// up to 8 s per video, and every photo thumbnail queued behind it waited too.
    static func poster(at url: URL) async -> UIImage? {
        let signposter = PerformanceSignposts.signposter
        let state = signposter.beginInterval("VideoPoster")
        let image = await generate(at: url)
        signposter.endInterval("VideoPoster", state)
        return image
    }

    // MARK: - Private

    private static func generate(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)

        // Cancelling the calling task stops the work, not just the wait: a remote file
        // that stalls (website video links) must free its `AsyncLimiter` slot.
        let work = CancellableWork(asset: asset, generator: generator)
        return await withTaskCancellationHandler {
            let duration = await assetDurationSeconds(asset)
            for seconds in candidateSeconds(duration: duration) {
                if Task.isCancelled { return nil }
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let still = await copyStill(generator, at: time) else { continue }
                if isUsable(still) { return still }
            }
            return nil
        } onCancel: {
            work.cancel()
        }
    }

    /// Lets the cancellation handler (which may run on any thread) stop loading.
    private final class CancellableWork: @unchecked Sendable {
        private let asset: AVURLAsset
        private let generator: AVAssetImageGenerator

        init(asset: AVURLAsset, generator: AVAssetImageGenerator) {
            self.asset = asset
            self.generator = generator
        }

        func cancel() {
            generator.cancelAllCGImageGeneration()
            asset.cancelLoading()
        }
    }

    private static func copyStill(
        _ generator: AVAssetImageGenerator,
        at time: CMTime
    ) async -> UIImage? {
        do {
            let cg = try await generator.image(at: time).image
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    private static func assetDurationSeconds(_ asset: AVURLAsset) async -> TimeInterval {
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    private static func clamp(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(0, time), max(duration - 0.04, 0))
    }

    private static func uniqued(_ values: [TimeInterval]) -> [TimeInterval] {
        var seen: [TimeInterval] = []
        for value in values {
            if seen.contains(where: { abs($0 - value) < 0.02 }) { continue }
            seen.append(value)
        }
        return seen
    }

    /// Matches `CameraManager.isNearlyBlack` — failed / encoder-black stills, not dim scenes.
    private static let luminanceContext = CIContext(options: [.workingColorSpace: NSNull()])

    private static func isNearlyBlack(_ image: UIImage) -> Bool {
        guard let ciImage = CIImage(image: image) else { return true }
        let extent = ciImage.extent
        guard extent.width > 1, extent.height > 1 else { return true }
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        ),
        let output = filter.outputImage
        else {
            return true
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        luminanceContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let luminance =
            0.299 * Double(pixel[0])
            + 0.587 * Double(pixel[1])
            + 0.114 * Double(pixel[2])
        return luminance < 14
    }
}
