//
//  CrossfadeLoopComposer.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Builds a looping player item whose end dissolves into its
//  start, so a clip that does not loop perfectly plays without a visible jump.
//  Thread Safety: Main thread only - AVFoundation composition objects are not Sendable
//

import AVFoundation
import os

// MARK: - CrossfadeLoopComposer

/// Turns a clip into a seamless loop by dissolving its last moments into its
/// first moments.
///
/// With clip length `D` and fade length `F`, the result is `D − F` long:
/// - Track A plays source `[F, D]` from time 0.
/// - Track B plays source `[0, F]` from time `D − 2F`, underneath A.
/// - Across `[D − 2F, D − F]` track A fades out over track B.
///
/// The last frame of the result is source time `F`, the same picture its
/// first frame shows, so restarting it is invisible. Audio fades the same way.
///
/// Thread Safety: The cache and its accessors are main thread only (`prepare`
/// runs on the main actor; the track loading it awaits runs off the main
/// thread). Results are cached per file URL so a replayed clip builds its
/// player item synchronously.
enum CrossfadeLoopComposer {

    // MARK: - Constants

    /// Length of the dissolve at the loop point, in seconds.
    static let fadeSeconds: Double = 1.0

    /// A clip must be at least this many fade lengths long to cross-fade.
    private static let minimumFadeMultiple: Double = 3

    /// Frame rate used when the clip does not report one.
    private static let fallbackFrameRate: Float = 30

    /// Highest frame rate the dissolve renders at.
    private static let maximumFrameRate: Float = 240

    /// Timescale for the fade times (matches the rest of the app's CMTimes).
    private static let timescale: CMTimeScale = 600

    /// Log for build failures.
    private static let logger = Logger(subsystem: "com.eclipsetv.app", category: "CrossfadeLoop")

    // MARK: - Cache

    /// Built loops keyed by file URL; `nil` value means "cannot cross-fade".
    private static var cache: [URL: CrossfadeLoopRecipe?] = [:]

    // MARK: - Public Interface

    /// Whether a recipe for `url` has been built (or ruled out) already.
    /// - Parameter url: Local video file URL
    /// - Returns: `true` when `cachedItem(for:)` gives a final answer
    static func isPrepared(_ url: URL) -> Bool {
        cache.keys.contains(url)
    }

    /// Whether a built, usable blend exists for `url`.
    /// - Parameter url: Local video file URL
    /// - Returns: `true` when `cachedItem(for:)` returns an item
    static func hasBlend(for url: URL) -> Bool {
        if case .some(.some) = cache[url] { return true }
        return false
    }

    /// A fresh player item for a prepared loop.
    /// - Parameter url: Local video file URL
    /// - Returns: The cross-faded item, or `nil` when the clip is too short,
    ///   has no picture, or has not been prepared yet
    static func cachedItem(for url: URL) -> AVPlayerItem? {
        guard let entry = cache[url], let recipe = entry else { return nil }
        return recipe.makeItem()
    }

    /// Builds (once) and caches the cross-faded loop for `url`.
    /// - Parameter url: Local video file URL
    @MainActor
    static func prepare(_ url: URL) async {
        guard !isPrepared(url) else { return }
        let recipe: CrossfadeLoopRecipe?
        do {
            recipe = try await buildRecipe(for: url)
        } catch {
            logger.error("Cross-fade loop failed: \(error.localizedDescription, privacy: .public)")
            recipe = nil
        }
        cache[url] = .some(recipe)
    }

    // MARK: - Private Helpers

    /// Loads the clip's tracks and assembles the overlapping composition.
    private static func buildRecipe(for url: URL) async throws -> CrossfadeLoopRecipe? {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric,
              duration.seconds >= fadeSeconds * minimumFadeMultiple,
              let video = try await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        let fade = CMTime(seconds: fadeSeconds, preferredTimescale: timescale)
        let timing = CrossfadeLoopTiming(duration: duration, fade: fade)
        let composition = AVMutableComposition()

        let videoTracks = try insertOverlapping(video, into: composition, timing: timing)
        let videoComposition = try await makeVideoComposition(
            source: video, tracks: videoTracks, timing: timing
        )
        var audioMix: AVAudioMix?
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let audioTracks = try insertOverlapping(audio, into: composition, timing: timing)
            audioMix = makeAudioMix(tracks: audioTracks, timing: timing)
        }
        return CrossfadeLoopRecipe(
            asset: composition, videoComposition: videoComposition, audioMix: audioMix
        )
    }

    /// Adds the "rest of clip" track and the overlapping "head of clip" track.
    /// - Returns: `(top, bottom)` — the track that fades out, and the one under it
    private static func insertOverlapping(
        _ source: AVAssetTrack,
        into composition: AVMutableComposition,
        timing: CrossfadeLoopTiming
    ) throws -> (top: AVMutableCompositionTrack, bottom: AVMutableCompositionTrack) {
        let invalid = kCMPersistentTrackID_Invalid
        guard let top = composition.addMutableTrack(withMediaType: source.mediaType,
                                                    preferredTrackID: invalid),
              let bottom = composition.addMutableTrack(withMediaType: source.mediaType,
                                                       preferredTrackID: invalid) else {
            throw CrossfadeLoopError.cannotAddTrack
        }
        try top.insertTimeRange(timing.tailSource, of: source, at: .zero)
        try bottom.insertTimeRange(timing.headSource, of: source, at: timing.fadeRange.start)
        return (top, bottom)
    }

    /// Plays the top track alone, then dissolves it into the bottom track.
    private static func makeVideoComposition(
        source: AVAssetTrack,
        tracks: (top: AVMutableCompositionTrack, bottom: AVMutableCompositionTrack),
        timing: CrossfadeLoopTiming
    ) async throws -> AVVideoComposition {
        let transform = try await source.load(.preferredTransform)
        let naturalSize = try await source.load(.naturalSize)
        let frameRate = try await source.load(.nominalFrameRate)

        let solo = AVMutableVideoCompositionInstruction()
        solo.timeRange = CMTimeRange(start: .zero, end: timing.fadeRange.start)
        solo.layerInstructions = [layer(for: tracks.top, transform: transform)]

        let blend = AVMutableVideoCompositionInstruction()
        blend.timeRange = timing.fadeRange
        let fadingOut = layer(for: tracks.top, transform: transform)
        fadingOut.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: timing.fadeRange)
        blend.layerInstructions = [fadingOut, layer(for: tracks.bottom, transform: transform)]

        let rendered = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let composition = AVMutableVideoComposition()
        composition.instructions = [solo, blend]
        composition.renderSize = CGSize(width: abs(rendered.width), height: abs(rendered.height))
        composition.frameDuration = CMTime(value: 1, timescale: frameTimescale(for: frameRate))
        return composition
    }

    /// Frames per second as a timescale, safe for damaged files that report
    /// zero, negative, infinite or absurd rates.
    /// - Parameter frameRate: The track's reported nominal frame rate
    /// - Returns: A whole rate between 1 and `maximumFrameRate`
    static func frameTimescale(for frameRate: Float) -> CMTimeScale {
        guard frameRate.isFinite, frameRate >= 1 else {
            return CMTimeScale(fallbackFrameRate)
        }
        return CMTimeScale(min(frameRate, maximumFrameRate).rounded())
    }

    /// One layer instruction that keeps the clip's orientation.
    private static func layer(
        for track: AVMutableCompositionTrack,
        transform: CGAffineTransform
    ) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instruction.setTransform(transform, at: .zero)
        return instruction
    }

    /// Fades the outgoing sound down while the incoming sound comes up.
    private static func makeAudioMix(
        tracks: (top: AVMutableCompositionTrack, bottom: AVMutableCompositionTrack),
        timing: CrossfadeLoopTiming
    ) -> AVAudioMix {
        let fadingOut = AVMutableAudioMixInputParameters(track: tracks.top)
        fadingOut.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: timing.fadeRange)
        let fadingIn = AVMutableAudioMixInputParameters(track: tracks.bottom)
        fadingIn.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: timing.fadeRange)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [fadingOut, fadingIn]
        return mix
    }
}

// MARK: - Supporting Types

/// Source and output time ranges for one cross-faded loop.
struct CrossfadeLoopTiming {

    /// Source range played first: everything after the first fade length.
    let tailSource: CMTimeRange

    /// Source range laid under the end: the first fade length of the clip.
    let headSource: CMTimeRange

    /// Output range where the tail dissolves into the head.
    let fadeRange: CMTimeRange

    /// Output length (clip length minus one fade length).
    let outputDuration: CMTime

    /// - Parameters:
    ///   - duration: Clip length
    ///   - fade: Dissolve length (must be under a third of `duration`)
    init(duration: CMTime, fade: CMTime) {
        tailSource = CMTimeRange(start: fade, end: duration)
        headSource = CMTimeRange(start: .zero, duration: fade)
        outputDuration = CMTimeSubtract(duration, fade)
        fadeRange = CMTimeRange(start: CMTimeSubtract(outputDuration, fade), duration: fade)
    }
}

/// A built composition that can stamp out player items on demand.
///
/// Thread Safety: Main thread only (holds non-Sendable AVFoundation objects).
struct CrossfadeLoopRecipe {

    /// The overlapping composition.
    let asset: AVAsset

    /// Picture dissolve.
    let videoComposition: AVVideoComposition

    /// Sound fade, when the clip has audio.
    let audioMix: AVAudioMix?

    /// A new player item carrying the dissolve and sound fade.
    func makeItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        return item
    }
}

/// Failures while assembling a cross-faded loop.
enum CrossfadeLoopError: Error {
    /// The composition refused a new track.
    case cannotAddTrack
}
