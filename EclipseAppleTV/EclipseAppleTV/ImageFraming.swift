//
//  ImageFraming.swift
//  EclipseAppleTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Normalized framing rectangle helpers mirroring the iPhone companion's framing math.
///
/// Must produce the same bitmap as `MediaCropGeometry` / `MediaAspect.framed` on iPhone
/// for a given `MediaFramingDTO`; the two are maintained by hand, not by
/// `Scripts/verify_shared_sources.sh`.
///
/// A framing is the region of the photo plane that fills the screen. It may run past the
/// photo along one axis — a framing between Fill and Fit shows bars there — but never
/// both, and never further than Fit.
enum ImageFraming {

    /// Point-space region inside an image of `imageSize` (top-left origin).
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

    /// Smallest `aspect` rect around `size`, centred: what Fit shows, bars included.
    static func fitRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        var width = size.width
        var height = width / aspect
        if height < size.height {
            height = size.height
            width = height * aspect
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Keeps `rect` between Fill and Fit, then keeps photo and rect overlapping fully.
    ///
    /// Along an axis where the rect is smaller than the photo, the rect stays inside the
    /// photo; where it is larger, the photo stays inside the rect. Neither case trims an
    /// overhanging edge: `cropping(to:)` returns the intersection rather than failing, so
    /// an overhanging rectangle would become a thin band.
    static func placed(_ rect: CGRect, in size: CGSize) -> CGRect? {
        guard size.width > 1, size.height > 1,
              rect.width > 1, rect.height > 1 else { return nil }
        let fit = fitRect(in: size, aspect: rect.width / rect.height)
        var width = rect.width
        var height = rect.height
        if width > fit.width + 0.01 {
            width = fit.width
            height = fit.height
        }
        guard width > 1, height > 1 else { return nil }
        return CGRect(
            x: clamped(rect.midX - width / 2, between: 0, and: size.width - width),
            y: clamped(rect.midY - height / 2, between: 0, and: size.height - height),
            width: width,
            height: height
        )
    }

    /// Whether `rect` runs past `size` and so shows bars when displayed.
    static func showsBars(_ rect: CGRect, in size: CGSize) -> Bool {
        rect.minX < -0.5 || rect.minY < -0.5
            || rect.maxX > size.width + 0.5 || rect.maxY > size.height + 0.5
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

    /// The bitmap the screen shows for `frameRect`: `image` cropped to it, or — where
    /// the rect runs past the photo — the photo drawn on black at its position inside
    /// the rect. The result's longest edge never exceeds the photo's.
    static func framed(_ image: UIImage, to frameRect: CGRect) -> UIImage? {
        let normalized = Self.normalized(image)
        let size = normalized.size
        guard frameRect.width > 0, frameRect.height > 0,
              size.width > 0, size.height > 0 else { return nil }
        guard showsBars(frameRect, in: size) else {
            return crop(normalized, to: frameRect)
        }
        let longest = max(size.width, size.height)
        let shrink = min(1, longest / max(frameRect.width, frameRect.height))
        let canvas = CGSize(
            width: (frameRect.width * shrink).rounded(),
            height: (frameRect.height * shrink).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = normalized.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            normalized.draw(in: CGRect(
                x: -frameRect.minX * shrink,
                y: -frameRect.minY * shrink,
                width: size.width * shrink,
                height: size.height * shrink
            ))
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

    /// Decode placement matching `apply(_:framing:fill:targetAspect:)`: a valid crop
    /// wins over Fit / Fill, so the decode is budgeted for the same region that ends
    /// up on screen.
    ///
    /// The stored rectangle is used as-is, before the display-aspect correction
    /// `apply` makes. That correction only grows the region, so the budget is a lower
    /// bound on what is rendered rather than an exact match.
    static func placement(
        framing: MediaFramingDTO?,
        fill: Bool
    ) -> StillDecodeBudget.Placement {
        if let framing, framing.width > 0, framing.height > 0 {
            return .crop(CGRect(
                x: framing.x, y: framing.y,
                width: framing.width, height: framing.height
            ))
        }
        return fill ? .fill : .fit
    }

    /// Applies a wire framing DTO: render at the framing then aspect-fit, or Fit / Fill
    /// contentMode.
    ///
    /// - Parameter targetAspect: Display aspect (width ÷ height) the framing is corrected
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
        guard let frameRect = placed(atAspect(raw, targetAspect), in: image.size) else {
            return (image, fill ? .scaleAspectFill : .scaleAspectFit)
        }
        return (framed(image, to: frameRect) ?? image, .scaleAspectFit)
    }

    /// `value` limited to the closed range between `a` and `b`, in either order.
    private static func clamped(_ value: CGFloat, between a: CGFloat, and b: CGFloat) -> CGFloat {
        min(max(value, min(a, b)), max(a, b))
    }
}
