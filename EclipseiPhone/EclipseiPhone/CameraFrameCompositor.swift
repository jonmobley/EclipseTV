//
//  CameraFrameCompositor.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Makes stills and movies match the live viewfinder (shape and frame overlay).
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

    /// Re-exports `sourceURL` to match the live viewfinder: trimmed to the output shape
    /// (the panel aspect-fills it, e.g. 9:16 in Vertical) and, when the setting is on,
    /// with the selected frame burned in. Nil when the recording already matches.
    ///
    /// Reads prefs/store on the main actor, then exports off the main thread.
    static func viewfinderVideoURLIfNeeded(from sourceURL: URL) async -> URL? {
        let (frame, aspect): (UIImage?, CGFloat) = await MainActor.run {
            let frame = ExternalOutputSettings.includeFrameInCaptures
                ? CameraFrameStore.shared.selectedImage
                : nil
            return (frame, MediaAspect.activeTarget)
        }
        do {
            return try await exportViewfinderVideo(
                from: sourceURL,
                aspect: aspect,
                frame: frame
            )
        } catch {
            return nil
        }
    }

    /// Exports a copy of `sourceURL` centre-cropped to `aspect` (when it differs) with
    /// `frame` aspect-fit over every video frame (when given). Nil when neither applies.
    static func exportViewfinderVideo(
        from sourceURL: URL,
        aspect: CGFloat?,
        frame: UIImage?
    ) async throws -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let displaySize = natural.applying(transform)
        let fullSize = CGSize(
            width: abs(displaySize.width),
            height: abs(displaySize.height)
        )
        guard fullSize.width > 2, fullSize.height > 2 else {
            throw ExportError.compositionFailed
        }
        let cropRect = aspect.flatMap {
            videoCropRect(for: fullSize, aspect: $0)
        }
        guard cropRect != nil || frame != nil else { return nil }
        let renderRect = cropRect ?? CGRect(origin: .zero, size: fullSize)
        let renderSize = renderRect.size

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
        // Upright first, then slide the trimmed window to the render origin.
        layerInstruction.setTransform(
            transform.concatenating(CGAffineTransform(
                translationX: -renderRect.minX,
                y: -renderRect.minY
            )),
            at: .zero
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        if let frame {
            videoComposition.animationTool = makeAnimationTool(
                frame: frame,
                renderSize: renderSize
            )
        }

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

    /// Centre crop for a video of `size` to `aspect`, snapped to whole even pixels
    /// (encoders reject odd dimensions); nil when the video already matches.
    static func videoCropRect(for size: CGSize, aspect: CGFloat) -> CGRect? {
        guard let rect = MediaAspect.centerCropRect(for: size, aspect: aspect) else {
            return nil
        }
        let width = (rect.width / 2).rounded(.down) * 2
        let height = (rect.height / 2).rounded(.down) * 2
        guard width >= 2, height >= 2 else { return nil }
        return CGRect(
            x: ((size.width - width) / 2).rounded(.down),
            y: ((size.height - height) / 2).rounded(.down),
            width: width,
            height: height
        )
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
