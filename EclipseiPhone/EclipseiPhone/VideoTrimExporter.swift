//
//  VideoTrimExporter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation

/// Writes the kept part of a video to a new file.
///
/// Copies the original picture and sound without re-encoding (fast, no quality loss);
/// only if the file can't be copied that way does it fall back to a high-quality
/// re-encode.
enum VideoTrimExporter {

    enum ExportError: Error {
        case invalidRange
        case exportUnavailable
    }

    /// - Returns: Temporary file URL of the trimmed video.
    static func export(sourceURL: URL, start: Double, end: Double) async throws -> URL {
        guard start.isFinite, end.isFinite, end - start > 0.05 else {
            throw ExportError.invalidRange
        }
        let asset = AVURLAsset(url: sourceURL)
        let timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        var lastError: Error = ExportError.exportUnavailable
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            let fileType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
            guard session.supportedFileTypes.contains(fileType) else { continue }
            let ext = fileType == .mp4 ? "mp4" : "mov"
            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("trim_\(UUID().uuidString).\(ext)")
            session.timeRange = timeRange
            do {
                try await session.export(to: outURL, as: fileType)
                return outURL
            } catch {
                try? FileManager.default.removeItem(at: outURL)
                lastError = error
            }
        }
        throw lastError
    }

    /// Video length in seconds, or 0 if it can't be read.
    static func durationSeconds(at url: URL) async -> Double {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : 0
    }
}
