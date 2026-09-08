//
//  AspectCropViewController+Geometry.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Crop Frame Geometry

extension AspectCropViewController {

    /// Sizes the white crop window to `targetAspect` inside the scroll view.
    func layoutCropFrame() {
        NSLayoutConstraint.deactivate(cropFrameConstraints)
        let maxW = scrollView.bounds.width - 32
        let maxH = scrollView.bounds.height - 32
        guard maxW > 0, maxH > 0 else { return }

        var cropW = maxW
        var cropH = cropW / targetAspect
        if cropH > maxH {
            cropH = maxH
            cropW = cropH * targetAspect
        }

        cropFrameConstraints = [
            cropFrameView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            cropFrameView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            cropFrameView.widthAnchor.constraint(equalToConstant: cropW),
            cropFrameView.heightAnchor.constraint(equalToConstant: cropH)
        ]
        NSLayoutConstraint.activate(cropFrameConstraints)
        view.layoutIfNeeded()
    }

    /// Configures zoom limits and restores `initialCropRect` or centers the image.
    ///
    /// Runs again if the crop window changes size after the first pass (safe area or
    /// size class settling during presentation), carrying the framing on screen over
    /// so the zoom floor and insets always belong to the window the user sees.
    func updateScrollMetricsIfNeeded() {
        guard scrollView.bounds.width > 0 else { return }
        let crop = cropFrameView.frame
        guard crop.width > 0, crop.height > 0 else { return }
        if didConfigureScroll {
            guard abs(crop.width - configuredCropSize.width) > 0.5
                || abs(crop.height - configuredCropSize.height) > 0.5 else { return }
            initialCropRect = visibleCropRectInImage() ?? initialCropRect
        }
        didConfigureScroll = true
        configuredCropSize = crop.size

        // `frame` is undefined on a transformed view, so drop to identity before
        // re-framing (see ZoomableImageView for the rotation bug this avoids).
        let imageSize = sourceImage.size
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        let scaleW = crop.width / imageSize.width
        let scaleH = crop.height / imageSize.height
        let minZoom = max(scaleW, scaleH)
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = max(minZoom * 4, minZoom + 0.01)

        let window = cropWindowInScrollFrame()
        scrollView.contentInset = UIEdgeInsets(
            top: window.minY,
            left: window.minX,
            bottom: scrollView.bounds.height - window.maxY,
            right: scrollView.bounds.width - window.maxX
        )

        if let initial = initialCropRect, applyInitialCrop(initial, cropFrame: crop) {
            return
        }

        // Center the image in the crop window at the zoom floor.
        let visible = CGSize(width: crop.width / minZoom, height: crop.height / minZoom)
        show(
            CGRect(
                x: (imageSize.width - visible.width) / 2,
                y: (imageSize.height - visible.height) / 2,
                width: visible.width,
                height: visible.height
            ),
            zoom: minZoom
        )
    }

    /// Dims everything outside the crop window.
    func updateDimMask() {
        let crop = cropFrameView.frame
        guard dimView.bounds.width > 0, crop.width > 0 else { return }
        let path = UIBezierPath(rect: dimView.bounds)
        let cropInDim = dimView.convert(crop, from: view)
        path.append(UIBezierPath(rect: cropInDim))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        dimView.layer.mask = mask
    }

    /// Visible crop frame mapped into source-image point space, clamped to the image.
    func visibleCropRectInImage() -> CGRect? {
        let bounds = CGRect(origin: .zero, size: sourceImage.size)
        let clamped = cropWindowInImageSpace().intersection(bounds)
        guard clamped.width > 1, clamped.height > 1 else { return nil }
        return clamped
    }

    /// The crop window in `imageView`'s bounds space — unscaled image points.
    ///
    /// Asks UIKit rather than recomputing from `contentOffset` and `zoomScale`: the
    /// conversion walks the scroll view's bounds origin and the zoom transform on
    /// `imageView`, so it is by construction the region shown through the window and
    /// cannot drift from it the way a separate formula can.
    func cropWindowInImageSpace() -> CGRect {
        imageView.convert(cropFrameView.bounds, from: cropFrameView)
    }

    // MARK: - Private

    /// Crop window relative to the scroll view's frame, independent of scroll position.
    ///
    /// `cropFrameView` and `scrollView` are siblings in `view`, so their frames share a
    /// coordinate space and the offset is a plain subtraction.
    private func cropWindowInScrollFrame() -> CGRect {
        cropFrameView.frame.offsetBy(
            dx: -scrollView.frame.minX,
            dy: -scrollView.frame.minY
        )
    }

    /// Restores scroll zoom/offset so `rect` fills the crop window. Returns false when
    /// the rect is unusable and the caller should fall back to centering.
    private func applyInitialCrop(_ rect: CGRect, cropFrame: CGRect) -> Bool {
        let imageSize = sourceImage.size
        let bounds = CGRect(origin: .zero, size: imageSize)
        let clamped = rect.intersection(bounds)
        guard clamped.width > 1, clamped.height > 1 else { return false }

        let zoom = max(
            cropFrame.width / clamped.width,
            cropFrame.height / clamped.height
        )
        let clampedZoom = min(
            max(zoom, scrollView.minimumZoomScale),
            scrollView.maximumZoomScale
        )
        show(clamped, zoom: clampedZoom)
        return true
    }

    /// Zooms to `zoom` and scrolls so `rect`'s origin sits at the window's top-left.
    ///
    /// The analytic offset is then corrected against `cropWindowInImageSpace()`, so
    /// the restore is exact even where the offset math and UIKit's layout disagree.
    private func show(_ rect: CGRect, zoom: CGFloat) {
        scrollView.zoomScale = zoom
        scrollView.contentOffset = CGPoint(
            x: rect.minX * zoom - scrollView.contentInset.left,
            y: rect.minY * zoom - scrollView.contentInset.top
        )
        let actual = cropWindowInImageSpace()
        let correction = CGPoint(
            x: (rect.minX - actual.minX) * zoom,
            y: (rect.minY - actual.minY) * zoom
        )
        guard abs(correction.x) > 0.01 || abs(correction.y) > 0.01 else { return }
        scrollView.contentOffset = CGPoint(
            x: scrollView.contentOffset.x + correction.x,
            y: scrollView.contentOffset.y + correction.y
        )
    }
}
