//
//  StillFramingGesture.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Crop math for pinching and dragging a still directly on the live preview.
///
/// Works in the image's own point space, like the framing editor. Every result goes
/// through `MediaCropGeometry.placed`, so a gesture can never produce a region that
/// zooms out past Fit or slides the photo off screen.
enum StillFramingGesture {

    /// Deepest zoom, as a fraction of the Fill region's width.
    static let maxZoom: CGFloat = 8

    /// What a finished gesture should save.
    enum Outcome: Equatable {
        /// Back at plain Fit or Fill: drop the custom position.
        case mode(MediaFitMode)
        /// A real custom position.
        case custom(MediaFraming)
    }

    /// The region on screen when a gesture starts.
    static func startRect(
        imageSize: CGSize,
        framing: MediaFraming?,
        mode: MediaFitMode,
        aspect: CGFloat
    ) -> CGRect {
        if let framing, let rect = framing.resolvedRect(in: imageSize, aspect: aspect) {
            return rect
        }
        return mode == .fill
            ? MediaCropGeometry.fillRect(in: imageSize, aspect: aspect)
            : MediaCropGeometry.fitRect(in: imageSize, aspect: aspect)
    }

    /// `rect` zoomed by `scale` (pinch: >1 zooms in), keeping the image point under
    /// `anchor` (unit position in the preview) where it is.
    static func zoomed(
        _ rect: CGRect,
        by scale: CGFloat,
        anchor: CGPoint,
        imageSize: CGSize
    ) -> CGRect {
        guard scale > 0, rect.width > 0, rect.height > 0 else { return rect }
        let aspect = rect.width / rect.height
        let fill = MediaCropGeometry.fillRect(in: imageSize, aspect: aspect)
        let fit = MediaCropGeometry.fitRect(in: imageSize, aspect: aspect)
        let width = min(max(rect.width / scale, fill.width / maxZoom), fit.width)
        let height = width / aspect
        let pinned = CGPoint(
            x: rect.minX + anchor.x * rect.width,
            y: rect.minY + anchor.y * rect.height
        )
        let next = CGRect(
            x: pinned.x - anchor.x * width,
            y: pinned.y - anchor.y * height,
            width: width,
            height: height
        )
        return MediaCropGeometry.placed(next, in: imageSize) ?? rect
    }

    /// `rect` moved so the picture follows a finger that travelled `translation`
    /// points across a preview of `viewSize` showing `rect` aspect-fit.
    static func panned(
        _ rect: CGRect,
        by translation: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              rect.width > 0, rect.height > 0 else { return rect }
        // Image points per preview point, for a region shown aspect-fit.
        let factor = max(rect.width / viewSize.width, rect.height / viewSize.height)
        let moved = rect.offsetBy(
            dx: -translation.x * factor,
            dy: -translation.y * factor
        )
        return MediaCropGeometry.placed(moved, in: imageSize) ?? rect
    }

    /// What to save for `rect` once the fingers lift.
    ///
    /// A region within a few percent of centred Fit or Fill snaps back to that mode,
    /// so pinching back out is a reset and swiping works again. When Fit and Fill are
    /// the same picture, the still keeps whichever mode it already had.
    static func outcome(
        for rect: CGRect,
        imageSize: CGSize,
        currentMode: MediaFitMode,
        tolerance: CGFloat = 0.03
    ) -> Outcome {
        guard rect.width > 0, rect.height > 0 else { return .mode(currentMode) }
        let aspect = rect.width / rect.height
        let fill = MediaCropGeometry.fillRect(in: imageSize, aspect: aspect)
        let fit = MediaCropGeometry.fitRect(in: imageSize, aspect: aspect)
        let matchesFill = matches(rect, fill, tolerance: tolerance)
        let matchesFit = matches(rect, fit, tolerance: tolerance)
        if matchesFill && matchesFit { return .mode(currentMode) }
        if matchesFill { return .mode(.fill) }
        if matchesFit { return .mode(.fit) }
        return .custom(MediaFraming(rect: rect, in: imageSize))
    }

    // MARK: - Private

    private static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        guard b.width > 0 else { return false }
        let slack = b.width * tolerance
        return abs(a.width - b.width) <= slack
            && abs(a.midX - b.midX) <= slack
            && abs(a.midY - b.midY) <= slack
    }
}
