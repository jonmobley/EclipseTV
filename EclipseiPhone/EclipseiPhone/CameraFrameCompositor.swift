//
//  CameraFrameCompositor.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Burns a PNG camera frame into stills and movies to match the live overlay.
enum CameraFrameCompositor {

    // MARK: - Photo

    /// Returns `still` with the selected frame aspect-fit on top when the setting is on.
    @MainActor
    static func stillWithFrameIfNeeded(_ still: UIImage) -> UIImage {
        guard ExternalOutputSettings.includeFrameInCaptures,
              let frame = CameraFrameStore.shared.selectedImage else {
            return still
        }
        return composite(still: still, frame: frame)
    }

    /// Aspect-fit overlays `frame` onto `still` (same as live `UIImageView` gravity).
    static func composite(still: UIImage, frame: UIImage) -> UIImage {
        let base = MediaAspect.normalized(still)
        let size = base.size
        guard size.width > 1, size.height > 1 else { return still }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = base.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            let bounds = CGRect(origin: .zero, size: size)
            frame.draw(in: aspectFitRect(for: frame.size, in: bounds))
        }
    }

    // MARK: - Video

    /// Burns the selected frame into `sourceURL` when the setting is on; else nil.
    ///
    /// Reads prefs/store on the main actor, then exports off the main thread.
    static func framedVideoURLIfNeeded(from sourceURL: URL) async -> URL? {
        let frame: UIImage? = await MainActor.run {
            guard ExternalOutputSettings.includeFrameInCaptures else { return nil }
            return CameraFrameStore.shared.selectedImage
        }
        guard let frame else { return nil }
        do {
            return try await burnFrame(frame, intoVideoAt: sourceURL)
        } catch {
            return nil
        }
    }

    /// Exports a copy of `sourceURL` with `frame` aspect-fit over every video frame.
    static func burnFrame(_ frame: UIImage, intoVideoAt sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let displaySize = natural.applying(transform)
        let renderSize = CGSize(
            width: abs(displaySize.width),
            height: abs(displaySize.height)
        )
        guard renderSize.width > 2, renderSize.height > 2 else {
            throw ExportError.compositionFailed
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionFailed
        }
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compTrack.insertTimeRange(timeRange, of: track, at: .zero)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audio = audioTracks.first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(timeRange, of: audio, at: .zero)
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: compTrack
        )
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = makeAnimationTool(
            frame: frame,
            renderSize: renderSize
        )

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EclipseFramed-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.compositionFailed
        }
        session.videoComposition = videoComposition
        try await session.export(to: outURL, as: .mov)
        return outURL
    }

    // MARK: - Geometry

    /// Centered aspect-fit rect for `contentSize` inside `bounds`.
    static func aspectFitRect(for contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(
            bounds.width / contentSize.width,
            bounds.height / contentSize.height
        )
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Private

    private static func makeAnimationTool(
        frame: UIImage,
        renderSize: CGSize
    ) -> AVVideoCompositionCoreAnimationTool {
        let parent = CALayer()
        let video = CALayer()
        let overlay = CALayer()
        let bounds = CGRect(origin: .zero, size: renderSize)
        parent.frame = bounds
        // Composition layers are bottom-left; flip so aspect-fit matches UIKit.
        parent.isGeometryFlipped = true
        video.frame = bounds
        overlay.frame = aspectFitRect(for: frame.size, in: bounds)
        overlay.contents = frame.cgImage
        overlay.contentsGravity = .resize
        parent.addSublayer(video)
        parent.addSublayer(overlay)
        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: video,
            in: parent
        )
    }

    enum ExportError: Error {
        case noVideoTrack
        case compositionFailed
    }
}
