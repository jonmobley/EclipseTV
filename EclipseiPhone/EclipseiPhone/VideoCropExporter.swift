//
//  VideoCropExporter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Exports a video cropped to a rect in the asset's display (orientation-applied) space.
enum VideoCropExporter {

    /// - Parameters:
    ///   - sourceURL: Input video.
    ///   - cropRect: Crop in display-oriented pixel coordinates (origin top-left).
    /// - Returns: Temporary file URL of the cropped export.
    static func export(sourceURL: URL, cropRect: CGRect) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let displaySize = natural.applying(transform)
        let renderSize = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))

        let cropped = cropRect.integral.intersection(
            CGRect(origin: .zero, size: renderSize)
        )
        guard cropped.width > 2, cropped.height > 2 else {
            throw ExportError.invalidCrop
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionFailed
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compTrack.insertTimeRange(timeRange, of: track, at: .zero)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audio = audioTracks.first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(timeRange, of: audio, at: .zero)
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        // Map natural → display, then translate so crop origin is at (0,0).
        var t = transform
        t = t.concatenating(
            CGAffineTransform(translationX: -cropped.origin.x, y: -cropped.origin.y)
        )
        layerInstruction.setTransform(t, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cropped.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crop_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.compositionFailed
        }
        session.videoComposition = videoComposition
        try await session.export(to: outURL, as: .mp4)
        return outURL
    }

    /// Renders a still frame for the crop UI at the video's display size.
    static func previewFrame(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1620, height: 2880)
        do {
            let cg = try await generator.image(at: .zero).image
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    enum ExportError: Error {
        case noVideoTrack
        case invalidCrop
        case compositionFailed
    }
}
