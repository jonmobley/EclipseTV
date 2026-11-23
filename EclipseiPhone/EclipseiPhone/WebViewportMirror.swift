//
//  WebViewportMirror.swift
//  EclipseiPhone
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  What part of a website the phone browser is showing, so the TV can show the same
//  part: pinch zoom plus where the page sits, across and down (2026-11-23). Positions
//  are fractions of how far the page can move, not points: the TV renders the same
//  logical viewport at a different scale, so its page size need not match exactly.
//

import UIKit

/// Zoom and position of a web page's scroll view, in a form both screens can apply.
struct WebViewportMirror: Equatable {
    /// Page zoom; 1 is the page at its own width.
    var zoomScale: CGFloat
    /// 0 = left edge, 1 = right edge (only moves while zoomed in).
    var progressX: CGFloat
    /// 0 = top, 1 = bottom.
    var progressY: CGFloat

    /// Reads a scroll view's state. Zoom never goes below `fitScale`, so the TV
    /// never shows a page smaller than the screen.
    init(zoomScale: CGFloat, contentOffset: CGPoint, contentSize: CGSize, boundsSize: CGSize) {
        self.zoomScale = max(zoomScale, Self.fitScale(
            zoomScale: zoomScale, contentWidth: contentSize.width, boundsWidth: boundsSize.width
        ))
        let maxX = contentSize.width - boundsSize.width
        let maxY = contentSize.height - boundsSize.height
        progressX = maxX > 0 ? min(max(contentOffset.x / maxX, 0), 1) : 0
        progressY = maxY > 0 ? min(max(contentOffset.y / maxY, 0), 1) : 0
    }

    init(zoomScale: CGFloat, progressX: CGFloat, progressY: CGFloat) {
        self.zoomScale = zoomScale
        self.progressX = progressX
        self.progressY = progressY
    }

    /// Where the scroll view should sit for this state, once its zoom is applied.
    func contentOffset(contentSize: CGSize, boundsSize: CGSize) -> CGPoint {
        let maxX = max(0, contentSize.width - boundsSize.width)
        let maxY = max(0, contentSize.height - boundsSize.height)
        return CGPoint(
            x: min(max(progressX, 0), 1) * maxX,
            y: min(max(progressY, 0), 1) * maxY
        )
    }

    /// Smallest zoom allowed: the page exactly fills the card's width. That is 1 for
    /// a normal page; a page laid out wider than the card may go down to its own
    /// width, so its whole width can still be shown.
    static func fitScale(zoomScale: CGFloat, contentWidth: CGFloat, boundsWidth: CGFloat) -> CGFloat {
        guard zoomScale > 0, contentWidth > 0, boundsWidth > 0 else { return 1 }
        let pageWidthAtOne = contentWidth / zoomScale
        return min(1, boundsWidth / pageWidthAtOne)
    }

    /// Puts a scroll view (the TV's web page) on this zoom and position. Never goes
    /// below the page's own smallest zoom.
    func apply(to scroll: UIScrollView) {
        let zoom = max(zoomScale, scroll.minimumZoomScale)
        if scroll.maximumZoomScale < zoom {
            scroll.maximumZoomScale = zoom
        }
        if abs(scroll.zoomScale - zoom) > 0.0005 {
            scroll.setZoomScale(zoom, animated: false)
        }
        let offset = contentOffset(contentSize: scroll.contentSize, boundsSize: scroll.bounds.size)
        if scroll.contentOffset != offset {
            scroll.contentOffset = offset
        }
    }
}
