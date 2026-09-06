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
    static func apply(
        _ image: UIImage,
        framing: MediaFramingDTO?,
        fill: Bool
    ) -> (image: UIImage, contentMode: UIView.ContentMode) {
        guard let framing,
              framing.width > 0, framing.height > 0 else {
            return (image, fill ? .scaleAspectFill : .scaleAspectFit)
        }
        let cropRect = rect(
            x: framing.x, y: framing.y,
            width: framing.width, height: framing.height,
            in: image.size
        )
        let cropped = crop(image, to: cropRect) ?? image
        return (cropped, .scaleAspectFit)
    }
}
