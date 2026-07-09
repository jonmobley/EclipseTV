//
//  ReceivedMediaValidator.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import ImageIO
import AVFoundation
import os.log

/// Validates peer-supplied media before it is committed into `Caches/Media`.
///
/// Extension checks alone are not enough: a connected peer can send arbitrary bytes
/// named `.jpg` / `.mp4`. This type confirms images decode via ImageIO and videos
/// expose at least one AVFoundation video track.
enum ReceivedMediaValidator {

    private static let logger = Logger(subsystem: "com.eclipsetv.app",
                                       category: "ReceivedMediaValidator")

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    enum Kind {
        case image
        case video
    }

    /// Infers media kind from a sanitized file extension, or `nil` if unsupported.
    static func kind(forExtension ext: String) -> Kind? {
        let lower = ext.lowercased()
        if imageExtensions.contains(lower) { return .image }
        if videoExtensions.contains(lower) { return .video }
        return nil
    }

    /// Returns true when `url` is a decodable image (ImageIO can open a source).
    static func isValidImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            logger.error("Rejected image: ImageIO could not open \(url.lastPathComponent, privacy: .public)")
            return false
        }
        return true
    }

    /// Returns true when `data` decodes as an image. Writes nothing to disk.
    static func isValidImage(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            logger.error("Rejected image data: ImageIO decode failed (\(data.count) bytes)")
            return false
        }
        return true
    }

    /// Returns true when `url` has at least one video track (synchronous probe).
    static func isValidVideo(at url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        let tracks = asset.tracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            logger.error("Rejected video: no video track in \(url.lastPathComponent, privacy: .public)")
            return false
        }
        return true
    }
}
