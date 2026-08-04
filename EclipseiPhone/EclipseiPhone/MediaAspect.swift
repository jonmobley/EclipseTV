//
//  MediaAspect.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// Helpers for Landscape (16:9) / Vertical (9:16) aspect checks and image cropping.
enum MediaAspect {
    /// Width ÷ height for Vertical library media.
    static let vertical: CGFloat = 9.0 / 16.0
    /// Width ÷ height for Landscape library media.
    static let landscape: CGFloat = 16.0 / 9.0

    /// Target aspect for the active Display Mode.
    static var activeTarget: CGFloat {
        ExternalOutputSettings.isVerticalMode ? vertical : landscape
    }

    /// Whether Vertical mode requires a crop step for non-matching media.
    static var requiresVerticalCrop: Bool {
        ExternalOutputSettings.isVerticalMode
    }

    /// True when `width/height` is within `tolerance` of `target` (relative).
    static func matches(_ size: CGSize, target: CGFloat, tolerance: CGFloat = 0.03) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let ratio = size.width / size.height
        return abs(ratio - target) / target <= tolerance
    }

    /// Pixel size with orientation applied (`.up` coordinates).
    static func orientedPixelSize(of image: UIImage) -> CGSize {
        let size = image.size
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: size.height, height: size.width)
        default:
            return size
        }
    }

    /// Returns a copy drawn with `.up` orientation for reliable cropping.
    static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Crops `image` to `cropRect` in the image's point space (origin top-left, `.up`).
    static func crop(_ image: UIImage, to cropRect: CGRect) -> UIImage? {
        let normalized = normalized(image)
        let scale = normalized.scale
        let pixelRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.size.width * scale,
            height: cropRect.size.height * scale
        ).integral
        guard let cgImage = normalized.cgImage,
              let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    /// Center-crops to 1:1 so landscape (or tall) covers fill Home’s square Recent tiles.
    static func centerCroppedToSquare(_ image: UIImage) -> UIImage {
        let normalized = normalized(image)
        let pointSize = normalized.size
        guard pointSize.width > 1, pointSize.height > 1 else { return image }
        let side = min(pointSize.width, pointSize.height)
        guard abs(pointSize.width - pointSize.height) > 0.5 else { return normalized }
        let rect = CGRect(
            x: (pointSize.width - side) / 2,
            y: (pointSize.height - side) / 2,
            width: side,
            height: side
        )
        return crop(normalized, to: rect) ?? normalized
    }

    /// Natural display size of a video (orientation applied when available).
    static func videoDisplaySize(at url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let size = natural.applying(transform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        } catch {
            return nil
        }
    }
}
