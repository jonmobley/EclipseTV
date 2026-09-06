//
//  ZoomableImageLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Scale math for Photos-style still preview zoom.
enum ZoomableImageLayout {
    /// Upper zoom relative to the fitted (minimum) scale.
    static let maxZoomMultiplier: CGFloat = 4
    /// Double-tap zoom relative to the fitted scale.
    static let doubleTapMultiplier: CGFloat = 3
    /// Relative slack above the fitted scale before a still counts as zoomed.
    static let zoomedTolerance: CGFloat = 0.001
    /// Fitted content within this many points of the bounds snaps to them exactly.
    static let contentSnapTolerance: CGFloat = 0.5

    /// Whether `zoomScale` is meaningfully past the fitted `minimumZoomScale`.
    ///
    /// Relative rather than absolute: a 12 MP photo fits a phone at roughly 0.1, so an
    /// absolute 0.01 slack let the image sit 10% zoomed while still reporting "fitted".
    static func isZoomed(zoomScale: CGFloat, minimumZoomScale: CGFloat) -> Bool {
        zoomScale > minimumZoomScale * (1 + zoomedTolerance)
    }

    /// Snaps any axis of `contentSize` within `contentSnapTolerance` of `boundsSize`.
    ///
    /// `image × (bounds / image)` can land a few ulps above `bounds` (3024 px on a
    /// 393 pt phone gives 393.00000000000006). UIScrollView treats any overflow as
    /// scrollable, so the still would rubber-band sideways instead of letting the
    /// gallery pager take the swipe.
    static func snappedContentSize(_ contentSize: CGSize, boundsSize: CGSize) -> CGSize {
        func snap(_ value: CGFloat, to bound: CGFloat) -> CGFloat {
            abs(value - bound) <= contentSnapTolerance ? bound : value
        }
        return CGSize(
            width: snap(contentSize.width, to: boundsSize.width),
            height: snap(contentSize.height, to: boundsSize.height)
        )
    }

    /// Minimum zoom so the image either fits or covers `boundsSize`.
    static func minimumScale(
        imageSize: CGSize,
        boundsSize: CGSize,
        fit: ZoomableImageView.MinimumFit
    ) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              boundsSize.width > 0, boundsSize.height > 0 else { return 1 }
        let xScale = boundsSize.width / imageSize.width
        let yScale = boundsSize.height / imageSize.height
        switch fit {
        case .contain: return min(xScale, yScale)
        case .cover: return max(xScale, yScale)
        }
    }

    /// Offset that centers `contentSize` inside `boundsSize` at the resting scale.
    ///
    /// Negative on an axis where the content is letterboxed (the offset sits inside the
    /// centering inset), positive where the content overflows (cover). Zero when equal.
    static func centeredContentOffset(contentSize: CGSize, boundsSize: CGSize) -> CGPoint {
        CGPoint(
            x: (contentSize.width - boundsSize.width) / 2,
            y: (contentSize.height - boundsSize.height) / 2
        )
    }
}
