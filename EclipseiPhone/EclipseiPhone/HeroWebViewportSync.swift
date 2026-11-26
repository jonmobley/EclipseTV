//
//  HeroWebViewportSync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Scroll-view delegate for the live website in the hero: when the
//               operator scrolls or pinches the page there, the TV shows the same
//               part (`WebViewportMirror`, as the full-screen browser does), and a
//               pinch never shrinks the page below its fit.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

// MARK: - HeroWebViewportSync

/// Sends the hero's website zoom and position to the external display.
final class HeroWebViewportSync: NSObject, UIScrollViewDelegate {

    // MARK: - Properties

    /// Whether the page in the hero is what the TV shows right now. Checked on
    /// every callback, so Lock / Blackout taking effect mid-scroll stops the TV
    /// following at once.
    var drivesOutput: () -> Bool = { false }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        pushIfOperatorMoved(scrollView)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        pushIfOperatorMoved(scrollView)
    }

    /// A pinch may shrink the page only to fit the hero, so no empty background
    /// shows. Set as the pinch starts: WebKit resets the range on page loads.
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollView.minimumZoomScale = WebViewportMirror.fitScale(
            zoomScale: scrollView.zoomScale,
            contentWidth: scrollView.contentSize.width,
            boundsWidth: scrollView.bounds.width
        )
    }

    /// Springs the page back to fit if it was pinched smaller anyway.
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let fit = WebViewportMirror.fitScale(
            zoomScale: scale,
            contentWidth: scrollView.contentSize.width,
            boundsWidth: scrollView.bounds.width
        )
        if scale < fit - 0.001 {
            scrollView.setZoomScale(fit, animated: true)
        }
        push(scrollView)
    }

    // MARK: - Internal

    /// Whether a scroll callback came from the operator's fingers (or the glide
    /// and bounce after them), not from the hero re-laying out the page.
    static func isOperatorMotion(
        tracking: Bool, decelerating: Bool, zooming: Bool, zoomBouncing: Bool
    ) -> Bool {
        tracking || decelerating || zooming || zoomBouncing
    }

    // MARK: - Private

    private func pushIfOperatorMoved(_ scrollView: UIScrollView) {
        guard Self.isOperatorMotion(
            tracking: scrollView.isTracking || scrollView.isDragging,
            decelerating: scrollView.isDecelerating,
            zooming: scrollView.isZooming,
            zoomBouncing: scrollView.isZoomBouncing
        ) else { return }
        push(scrollView)
    }

    private func push(_ scrollView: UIScrollView) {
        guard drivesOutput() else { return }
        ExternalDisplayManager.shared.setWebViewport(WebViewportMirror(
            zoomScale: scrollView.zoomScale,
            contentOffset: scrollView.contentOffset,
            contentSize: scrollView.contentSize,
            boundsSize: scrollView.bounds.size
        ))
    }
}
