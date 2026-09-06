//
//  PresentationImageDecoder.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import ImageIO
import UIKit

/// Decodes fullscreen presentation stills off the main thread at display size.
///
/// `UIImage(contentsOfFile:)` is lazy: a 12 MP photo decodes on the main thread at
/// first paint and hitchs the AirPlay encode. ImageIO downsamples to the external
/// screen's native pixel edge and `preparingForDisplay()` forces the decode here.
enum PresentationImageDecoder {

    /// Default longest-edge ceiling when no external screen bounds are known (1080p).
    static let fallbackMaxPixelEdge = 1920

    /// Longest edge of `screen`'s native bounds, or `fallbackMaxPixelEdge`.
    static func maxPixelEdge(for screen: UIScreen?) -> Int {
        guard let screen else { return fallbackMaxPixelEdge }
        let bounds = screen.nativeBounds
        let edge = max(bounds.width, bounds.height)
        guard edge.isFinite, edge > 0 else { return fallbackMaxPixelEdge }
        return Int(edge.rounded(.up))
    }

    /// Decodes `fileURL` downsampled so its longest edge is at most `maxPixelEdge`.
    ///
    /// Must be called off the main thread. Returns a display-ready bitmap, or nil
    /// when the file is missing or not a readable image.
    ///
    /// - Parameters:
    ///   - fileURL: Local image file.
    ///   - maxPixelEdge: Longest-edge ceiling in pixels (external screen native size).
    nonisolated static func decode(
        fileURL: URL,
        maxPixelEdge: Int
    ) -> UIImage? {
        guard let image = ThumbnailDecoder.decode(
            fileURL: fileURL,
            maxPixelEdge: max(1, maxPixelEdge)
        ) else { return nil }
        return image.preparingForDisplay() ?? image
    }
}
