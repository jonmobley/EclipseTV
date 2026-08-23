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

    /// Times to try, in order. First frame is preferred when it isn’t black.
    static func candidateSeconds(duration: TimeInterval) -> [TimeInterval] {
        let end = duration.isFinite ? max(duration, 0) : 0
        if end < 0.35 {
            return uniqued(
                [end * 0.5, end * 0.75, 0].map { clamp($0, duration: end) }
            )
        }
        let points: [TimeInterval] = [0, 0.2, 0.5, 1.0, 2.0, min(3.0, end * 0.45)]
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
    static func image(at url: URL) -> UIImage? {
        let semaphore = DispatchSemaphore(value: 0)
        var image: UIImage?
        Task {
            image = await generate(at: url)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 8)
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

        let duration = await assetDurationSeconds(asset)
        for seconds in candidateSeconds(duration: duration) {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let still = await copyStill(generator, at: time) else { continue }
            if isUsable(still) { return still }
        }
        return nil
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
