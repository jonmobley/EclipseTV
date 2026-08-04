//
//  ThumbnailDecoder.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import ImageIO
import UIKit

/// Decodes grid-sized thumbnails without ever materialising a full-size bitmap.
///
/// `UIImage(contentsOfFile:)` decodes at full resolution: a 12-megapixel photo becomes
/// roughly 48 MB of pixels for a tile a few hundred points wide. ImageIO can decode
/// straight to the size actually needed instead.
enum ThumbnailDecoder {

    /// Longest-edge ceiling in pixels — a full-width tile on a 3× screen.
    static let maxPixelEdge = 640

    /// Decodes `fileURL` downsampled so its longest edge is at most `maxPixelEdge`.
    ///
    /// - Parameters:
    ///   - fileURL: Image file to read.
    ///   - maxPixelEdge: Longest-edge ceiling in pixels.
    /// - Returns: A fully decoded, upright image, or nil when the file is missing or is
    ///   not a readable image.
    static func decode(fileURL: URL, maxPixelEdge: Int = maxPixelEdge) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode on this (background) thread — don’t defer to first main-thread paint.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelEdge
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Downsamples an already-decoded image (video stills, received transfers).
    ///
    /// - Parameters:
    ///   - image: Source image; returned unchanged when already small enough.
    ///   - maxPixelEdge: Longest-edge ceiling in pixels.
    static func downsample(_ image: UIImage, maxPixelEdge: Int = maxPixelEdge) -> UIImage {
        let limit = CGFloat(maxPixelEdge)
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > limit, longest > 0 else { return image }
        let target = CGSize(
            width: pixelSize.width * limit / longest,
            height: pixelSize.height * limit / longest
        )
        return image.preparingThumbnail(of: target) ?? image
    }
}
