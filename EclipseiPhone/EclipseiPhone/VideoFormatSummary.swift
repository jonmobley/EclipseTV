//
//  VideoFormatSummary.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import CoreGraphics

/// Display size and frame rate of a local video, for user-facing labels.
///
/// Read straight off the first video track so the numbers describe the file the user
/// picked rather than anything the app does with it afterwards.
enum VideoFormatSummary {

    struct Info: Equatable {
        /// Orientation-applied pixel size.
        let displaySize: CGSize
        /// Frames per second, or nil when the track reports nothing believable.
        let framesPerSecond: Double?
    }

    /// Frame rates believable enough to show, matching `VideoCropExporter.frameRateRange`.
    static let frameRateRange: ClosedRange<Double> = 1...240

    /// Reads `url`'s first video track, or nil when it has none.
    static func load(from url: URL) async -> Info? {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let nominal = try await track.load(.nominalFrameRate)
            let minFrameDuration = try await track.load(.minFrameDuration)
            let size = natural.applying(transform)
            return Info(
                displaySize: CGSize(width: abs(size.width), height: abs(size.height)),
                framesPerSecond: frameRate(
                    nominalFrameRate: nominal, minFrameDuration: minFrameDuration
                )
            )
        } catch {
            return nil
        }
    }

    /// Frames per second from track metadata, or nil when neither source is believable.
    ///
    /// Prefers `nominalFrameRate` — the opposite of `VideoCropExporter`, which needs an
    /// exact rational to encode with. Here the typical rate is the more honest label for
    /// a variable-rate file, and the rounding in `frameRateText` hides the difference.
    static func frameRate(nominalFrameRate: Float, minFrameDuration: CMTime) -> Double? {
        let nominal = Double(nominalFrameRate)
        if nominal.isFinite, frameRateRange.contains(nominal) { return nominal }
        guard minFrameDuration.isNumeric, minFrameDuration.seconds > 0 else { return nil }
        let derived = 1 / minFrameDuration.seconds
        return frameRateRange.contains(derived) ? derived : nil
    }

    /// "1080 × 1920  ·  60 fps", dropping either half when it is unknown.
    static func describe(_ info: Info) -> String {
        var parts: [String] = []
        let size = info.displaySize
        if size.width >= 1, size.height >= 1 {
            parts.append("\(Int(size.width.rounded())) × \(Int(size.height.rounded()))")
        }
        if let fps = info.framesPerSecond {
            parts.append("\(frameRateText(fps)) fps")
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Whole numbers when the rate is within rounding distance of one, so NTSC 23.976 and
    /// 29.97 read as the 24 and 30 people expect. One decimal otherwise.
    static func frameRateText(_ fps: Double) -> String {
        let rounded = fps.rounded()
        if abs(fps - rounded) < 0.05 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", fps)
    }
}
