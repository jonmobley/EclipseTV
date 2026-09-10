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
/// A `MediaFraming` is a unit rectangle. It records neither the bitmap it was measured
/// against nor the Display Mode it was measured for, so denormalising it against a
/// differently shaped bitmap — or after the user switches Landscape ↔ Vertical, or on
/// a device that saved it in the other mode — yields a rectangle that is no longer the
/// display aspect. `CGImage.cropping(to:)` then returns the *intersection* rather than
/// failing, so an overhanging rectangle becomes a thin band with no error anywhere.
///
/// Both corrections live here so the editor and every consumer give one answer.
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

    /// Moves `rect` inside `size`, shrinking about its centre only when it will not fit.
    ///
    /// Never trims a single overhanging edge — that is what turns a crop window hanging
    /// off the photo into a thin strip.
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

    /// The crop to actually use: `aspect`-shaped, centred on `rect`, inside `size`.
    static func resolved(_ rect: CGRect, in size: CGSize, aspect: CGFloat) -> CGRect? {
        containedIn(atAspect(rect, aspect), size)
    }
}
