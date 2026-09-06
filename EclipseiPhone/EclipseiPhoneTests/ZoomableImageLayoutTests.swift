//
//  ZoomableImageLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct ZoomableImageLayoutTests {

    @Test func containUsesTheSmallerAxis() {
        let scale = ZoomableImageLayout.minimumScale(
            imageSize: CGSize(width: 4000, height: 3000),
            boundsSize: CGSize(width: 400, height: 800),
            fit: .contain
        )
        #expect(scale == 0.1)
    }

    @Test func coverUsesTheLargerAxis() {
        let scale = ZoomableImageLayout.minimumScale(
            imageSize: CGSize(width: 4000, height: 3000),
            boundsSize: CGSize(width: 400, height: 800),
            fit: .cover
        )
        #expect(abs(scale - (800.0 / 3000.0)) < 0.0001)
    }

    @Test func emptySizesReturnOne() {
        let emptyImage = ZoomableImageLayout.minimumScale(
            imageSize: .zero,
            boundsSize: CGSize(width: 100, height: 100),
            fit: .contain
        )
        let emptyBounds = ZoomableImageLayout.minimumScale(
            imageSize: CGSize(width: 100, height: 100),
            boundsSize: .zero,
            fit: .cover
        )
        #expect(emptyImage == 1)
        #expect(emptyBounds == 1)
    }

    @Test func maxZoomIsFourTimesFit() {
        #expect(ZoomableImageLayout.maxZoomMultiplier == 4)
    }

    /// The zoomed threshold is relative to the fitted scale, so a large photo that fits
    /// at ~0.1 does not report "fitted" while visibly 10% zoomed.
    @Test func zoomedThresholdIsRelativeToFit() {
        let fit: CGFloat = 393.0 / 4032.0
        #expect(!ZoomableImageLayout.isZoomed(zoomScale: fit, minimumZoomScale: fit))
        #expect(!ZoomableImageLayout.isZoomed(zoomScale: fit * 0.9, minimumZoomScale: fit))
        #expect(ZoomableImageLayout.isZoomed(zoomScale: fit * 1.02, minimumZoomScale: fit))
        #expect(ZoomableImageLayout.isZoomed(zoomScale: fit + 0.005, minimumZoomScale: fit))
    }

    @Test func snappedContentSizePinsFloatOvershootToBounds() {
        let bounds = CGSize(width: 393, height: 852)
        let overshoot = ZoomableImageLayout.snappedContentSize(
            CGSize(width: 393.00000000000006, height: 524.0000000000001),
            boundsSize: bounds
        )
        #expect(overshoot == CGSize(width: 393, height: 524.0000000000001))

        let zoomed = ZoomableImageLayout.snappedContentSize(
            CGSize(width: 786, height: 1048),
            boundsSize: bounds
        )
        #expect(zoomed == CGSize(width: 786, height: 1048))
    }

    /// A portrait 12 MP iPhone photo on a 393 pt-wide phone is the everyday case where
    /// `image × (bounds / image)` overshoots by a few ulps. The hosting scroll view must
    /// not think it can scroll sideways, or it steals the swipe from the gallery pager.
    @MainActor
    @Test func fittedContentNeverOvershootsBoundsWidth() {
        let view = ZoomableImageView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        view.image = makeImage(size: CGSize(width: 3024, height: 4032))
        view.layoutIfNeeded()
        guard let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first else {
            Issue.record("expected a hosting scroll view")
            return
        }
        #expect(scroll.contentSize.width <= scroll.bounds.width)
        #expect(scroll.contentSize.height <= scroll.bounds.height)
        #expect(!view.isZoomed)

        scroll.zoomScale = scroll.minimumZoomScale * 2
        #expect(view.isZoomed)
        view.resetZoom(animated: false)
        #expect(scroll.contentSize.width <= scroll.bounds.width)
        #expect(!view.isZoomed)
    }

    @Test func centeredOffsetIsNegativeWhenLetterboxedAndPositiveWhenOverflowing() {
        let letterboxed = ZoomableImageLayout.centeredContentOffset(
            contentSize: CGSize(width: 400, height: 225),
            boundsSize: CGSize(width: 400, height: 800)
        )
        #expect(letterboxed == CGPoint(x: 0, y: -287.5))

        let overflowing = ZoomableImageLayout.centeredContentOffset(
            contentSize: CGSize(width: 1422, height: 800),
            boundsSize: CGSize(width: 400, height: 800)
        )
        #expect(overflowing == CGPoint(x: 511, y: 0))
    }

    /// Portrait → landscape → portrait must land back on the fitted scale with the
    /// image at its natural size. Re-framing while the zoom transform was applied
    /// used to inflate the image on every turn until it could no longer fit.
    @MainActor
    @Test func rotatingBackAndForthReturnsToFit() {
        let image = makeImage(size: CGSize(width: 1600, height: 900))
        let view = ZoomableImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        view.image = image
        view.layoutIfNeeded()
        guard let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first else {
            Issue.record("expected a hosting scroll view")
            return
        }
        let portraitFit = CGSize(width: 400, height: 225)
        #expect(approximately(scroll.contentSize, portraitFit))
        #expect(!view.isZoomed)

        view.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutIfNeeded()
        #expect(approximately(scroll.contentSize, CGSize(width: 711.1, height: 400)))
        #expect(!view.isZoomed)
        #expect(scroll.zoomScale <= scroll.minimumZoomScale + 0.0001)

        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        #expect(approximately(scroll.contentSize, portraitFit))
        #expect(!view.isZoomed)
        #expect(scroll.contentOffset.y < 0, "letterboxed image should sit centered")
    }

    @MainActor
    @Test func rotatingWhileZoomedRefitsInsteadOfCarryingTheZoom() {
        let view = ZoomableImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        view.image = makeImage(size: CGSize(width: 1600, height: 900))
        view.layoutIfNeeded()
        guard let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first else {
            Issue.record("expected a hosting scroll view")
            return
        }
        scroll.zoomScale = scroll.minimumZoomScale * 3
        #expect(view.isZoomed)

        view.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutIfNeeded()
        #expect(!view.isZoomed)
        #expect(approximately(scroll.contentSize, CGSize(width: 711.1, height: 400)))
    }

    /// UIKit lays out inside the rotation animation, so the refit's implicit animations
    /// are what the user watches during a turn. Refitting used to move `zoomScale`
    /// twice — once through identity to re-frame the image — and the two additive
    /// transform deltas multiplied into a curve that ballooned the still to several
    /// times its fitted size mid-turn before settling.
    @MainActor
    @Test func rotatingScalesStraightBetweenTheTwoFittedSizes() {
        let portrait = CGRect(x: 0, y: 0, width: 393, height: 852)
        let window = UIWindow(frame: portrait)
        let view = ZoomableImageView(frame: portrait)
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.image = makeImage(size: CGSize(width: 2400, height: 1800))
        view.layoutIfNeeded()
        guard let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first,
              let content = scroll.subviews.compactMap({ $0 as? UIImageView }).first else {
            Issue.record("expected a hosting scroll view around an image view")
            return
        }

        UIView.animate(withDuration: 0.3) {
            view.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
            view.layoutIfNeeded()
        }

        let start = presentedScale(of: content, atProgress: 0)
        let middle = presentedScale(of: content, atProgress: 0.5)
        let end = presentedScale(of: content, atProgress: 1)
        #expect(abs(start - 393.0 / 2400.0) < 0.001, "turn starts at the portrait fit")
        #expect(abs(end - 393.0 / 1800.0) < 0.001, "turn ends at the landscape fit")
        #expect(middle <= max(start, end) * 1.01, "no bulge between the two fits")
        #expect(middle >= min(start, end) * 0.99, "no dip between the two fits")
    }

    /// Scale the image layer renders at `progress` through its pending animations,
    /// composing them the way Core Animation does.
    @MainActor
    private func presentedScale(of view: UIView, atProgress progress: CGFloat) -> CGFloat {
        var scale = view.layer.transform.m11
        for key in view.layer.animationKeys() ?? [] {
            guard let basic = view.layer.animation(forKey: key) as? CABasicAnimation,
                  basic.keyPath == "transform",
                  let from = (basic.fromValue as? NSValue)?.caTransform3DValue.m11,
                  let to = (basic.toValue as? NSValue)?.caTransform3DValue.m11 else { continue }
            let value = from + (to - from) * progress
            scale = basic.isAdditive ? scale * value : value
        }
        return scale
    }

    private func approximately(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
