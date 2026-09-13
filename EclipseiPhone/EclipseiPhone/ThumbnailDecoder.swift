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
        decode(fileURL: fileURL) { _ in maxPixelEdge }
    }

    /// Decodes `fileURL` with a ceiling chosen from the encoded image's own size.
    ///
    /// Reads only the header before deciding, so a fullscreen Fill can ask for exactly
    /// the pixels its crop will show without first decoding the whole file.
    ///
    /// - Parameters:
    ///   - fileURL: Image file to read.
    ///   - maxPixelEdge: Receives the upright pixel size of the encoded image and returns
    ///     the longest-edge ceiling in pixels. Receives `.zero` when the header carries
    ///     no dimensions.
    static func decode(
        fileURL: URL,
        maxPixelEdge: (CGSize) -> Int
    ) -> UIImage? {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            return nil
        }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return nil
        }
        let edge = maxPixelEdge(uprightPixelSize(of: source) ?? .zero)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode on this (background) thread — don’t defer to first main-thread paint.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, edge)
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Pixel size of the first image as it will appear once EXIF orientation is applied.
    ///
    /// Header-only: no pixels are decoded. Orientations 5–8 are the rotated ones, so
    /// their stored width and height swap.
    static func uprightPixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = CGSize(width: width.doubleValue, height: height.doubleValue)
        guard size.width > 0, size.height > 0 else { return nil }
        return orientation >= 5
            ? CGSize(width: size.height, height: size.width)
            : size
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
