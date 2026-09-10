//
//  ImageFraming.swift
//  EclipseAppleTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Normalized crop rectangle helpers mirroring the iPhone companion's framing math.
///
/// Must produce the same crop as `MediaFraming` / `MediaAspect.crop` on iPhone for a
/// given `MediaFramingDTO`; the two are maintained by hand, not by
/// `Scripts/verify_shared_sources.sh`.
enum ImageFraming {

    /// Point-space crop inside an image of `imageSize` (top-left origin).
    static func rect(
        x: Double, y: Double, width: Double, height: Double,
        in imageSize: CGSize
    ) -> CGRect {
        CGRect(
            x: x * imageSize.width,
            y: y * imageSize.height,
            width: width * imageSize.width,
            height: height * imageSize.height
        )
    }

    /// Grows `rect` about its centre until it is exactly `aspect` (width ÷ height).
    static func atAspect(_ rect: CGRect, _ aspect: CGFloat) -> CGRect {
        guard rect.width > 0, rect.height > 0, aspect > 0 else { return rect }
        var width = rect.width
        var height = rect.height
        if width / height > aspect {
            height = width / aspect
        } else {
            width = height * aspect
        }
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Moves `rect` inside `size`, shrinking about its centre only when it will not fit.
    ///
    /// Never trims a single overhanging edge: `cropping(to:)` returns the intersection
    /// rather than failing, so an overhanging rectangle would become a thin band.
    static func containedIn(_ rect: CGRect, _ size: CGSize) -> CGRect? {
        guard size.width > 1, size.height > 1,
              rect.width > 1, rect.height > 1 else { return nil }
        let aspect = rect.width / rect.height
        var width = min(rect.width, size.width)
        var height = min(rect.height, size.height)
        if width / height > aspect {
            width = height * aspect
        } else {
            height = width / aspect
        }
        guard width > 1, height > 1 else { return nil }
        return CGRect(
            x: min(max(rect.midX - width / 2, 0), size.width - width),
            y: min(max(rect.midY - height / 2, 0), size.height - height),
            width: width,
            height: height
        )
    }

    /// Crops `image` to `cropRect` in the image's point space (origin top-left, `.up`).
    static func crop(_ image: UIImage, to cropRect: CGRect) -> UIImage? {
        let normalized = Self.normalized(image)
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

    /// Applies a wire framing DTO: crop then aspect-fit, or Fit / Fill contentMode.
    ///
    /// - Parameter targetAspect: Display aspect (width ÷ height) the crop is corrected
    ///   to. The DTO is a unit rectangle carrying no record of the bitmap it was
    ///   measured against, so applying it raw to a differently shaped one showed a thin
    ///   band instead of the region the user framed.
    static func apply(
        _ image: UIImage,
        framing: MediaFramingDTO?,
        fill: Bool,
        targetAspect: CGFloat
    ) -> (image: UIImage, contentMode: UIView.ContentMode) {
        guard let framing,
              framing.width > 0, framing.height > 0 else {
            return (image, fill ? .scaleAspectFill : .scaleAspectFit)
        }
        let raw = rect(
            x: framing.x, y: framing.y,
            width: framing.width, height: framing.height,
            in: image.size
        )
        guard let cropRect = containedIn(atAspect(raw, targetAspect), image.size) else {
            return (image, fill ? .scaleAspectFill : .scaleAspectFit)
        }
        let cropped = crop(image, to: cropRect) ?? image
        return (cropped, .scaleAspectFit)
    }
}
