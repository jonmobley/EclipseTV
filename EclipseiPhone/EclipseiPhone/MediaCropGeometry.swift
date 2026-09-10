//
//  MediaCropGeometry.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Shape corrections shared by the framing editor and everything that applies a
/// saved framing.
///
/// A `MediaFraming` is a unit rectangle describing the region of the photo plane that
/// fills the screen. It may run past the photo's edges along one axis — that is how a
/// framing between Fill and Fit (black bars) is represented — but never both, and never
/// further than Fit. The rectangle records neither the bitmap it was measured against
/// nor the Display Mode it was measured for, so denormalising it against a differently
/// shaped bitmap, or after a Landscape ↔ Vertical switch, yields a rectangle that is no
/// longer the display aspect. Both corrections live here so the editor and every
/// consumer give one answer.
enum MediaCropGeometry {

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

    /// Largest `aspect` rect inside `size`, centred: what Fill shows.
    static func fillRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        return centred(CGSize(width: width, height: height), in: size)
    }

    /// Smallest `aspect` rect around `size`, centred: what Fit shows, bars included.
    static func fitRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        var width = size.width
        var height = width / aspect
        if height < size.height {
            height = size.height
            width = height * aspect
        }
        return centred(CGSize(width: width, height: height), in: size)
    }

    /// Keeps `rect` between Fill and Fit, then keeps photo and rect overlapping fully.
    ///
    /// Along an axis where the rect is smaller than the photo, the rect stays inside the
    /// photo; where it is larger, the photo stays inside the rect. Neither case trims an
    /// overhanging edge — that is what turns a crop window hanging off the photo into a
    /// thin strip. A rect larger than Fit shrinks about its centre to Fit.
    static func placed(_ rect: CGRect, in size: CGSize) -> CGRect? {
        guard size.width > 1, size.height > 1,
              rect.width > 1, rect.height > 1 else { return nil }
        let aspect = rect.width / rect.height
        let fit = fitRect(in: size, aspect: aspect)
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

    /// The region to actually show: `aspect`-shaped, centred on `rect`, placed.
    static func resolved(_ rect: CGRect, in size: CGSize, aspect: CGFloat) -> CGRect? {
        placed(atAspect(rect, aspect), in: size)
    }

    /// Whether `rect` runs past `size` and so shows bars when displayed.
    static func showsBars(_ rect: CGRect, in size: CGSize) -> Bool {
        rect.minX < -0.5 || rect.minY < -0.5
            || rect.maxX > size.width + 0.5 || rect.maxY > size.height + 0.5
    }

    // MARK: - Private

    private static func centred(_ inner: CGSize, in outer: CGSize) -> CGRect {
        CGRect(
            x: (outer.width - inner.width) / 2,
            y: (outer.height - inner.height) / 2,
            width: inner.width,
            height: inner.height
        )
    }

    /// `value` limited to the closed range between `a` and `b`, in either order.
    private static func clamped(_ value: CGFloat, between a: CGFloat, and b: CGFloat) -> CGFloat {
        min(max(value, min(a, b)), max(a, b))
    }
}
