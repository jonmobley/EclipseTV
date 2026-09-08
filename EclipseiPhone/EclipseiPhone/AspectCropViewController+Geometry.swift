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
    func updateScrollMetricsIfNeeded() {
        guard !didConfigureScroll, scrollView.bounds.width > 0 else { return }
        let crop = cropFrameView.frame
        guard crop.width > 0, crop.height > 0 else { return }
        didConfigureScroll = true

        let imageSize = sourceImage.size
        // `frame` is undefined on a transformed view, so drop any zoom before
        // re-framing at natural size (a no-op on the first pass).
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
        configuredCropWindow = window
        scrollView.contentInset = UIEdgeInsets(
            top: window.minY,
            left: window.minX,
            bottom: scrollView.bounds.height - window.maxY,
            right: scrollView.bounds.width - window.maxX
        )

        if let initial = initialCropRect, applyInitialCrop(initial, cropFrame: crop) {
            return
        }

        // Center the image in the crop window.
        scrollView.zoomScale = minZoom
        let scaled = CGSize(
            width: imageSize.width * minZoom,
            height: imageSize.height * minZoom
        )
        let offsetX = max((scaled.width - crop.width) / 2, 0)
        let offsetY = max((scaled.height - crop.height) / 2, 0)
        scrollView.contentOffset = CGPoint(
            x: offsetX - scrollView.contentInset.left,
            y: offsetY - scrollView.contentInset.top
        )
    }

    /// Re-derives insets and zoom limits when a later layout moved the crop window.
    ///
    /// The first layout pass can run before the safe area settles, and rotation moves
    /// the window too. Insets are what let the image's edges reach the window's edges,
    /// so stale ones let the user pan past the photo — and the saved rect then gets
    /// clamped to a region that doesn't match what the window showed. Carry the region
    /// on screen through the new geometry instead.
    func reconfigureScrollIfWindowMoved() {
        guard didConfigureScroll else { return }
        let window = cropWindowInScrollFrame()
        guard window.width > 0, window.height > 0,
              !window.isClose(to: configuredCropWindow) else { return }
        initialCropRect = visibleCropRect(window: configuredCropWindow)
        didConfigureScroll = false
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

    /// Visible crop frame mapped into source-image point space.
    ///
    /// Inverse of `applyInitialCrop`: the window's frame-space origin plus
    /// `contentOffset` is its position in zoomed content space. Do not route the window
    /// through `scrollView.convert(_:from:)` here — a scroll view's bounds origin *is*
    /// its `contentOffset`, so that result already includes the offset.
    func visibleCropRectInImage() -> CGRect? {
        visibleCropRect(window: cropWindowInScrollFrame())
    }

    // MARK: - Private

    /// Image-space region under `window` (scroll-frame space) at the current scroll
    /// zoom and offset.
    private func visibleCropRect(window: CGRect) -> CGRect? {
        let scale = scrollView.zoomScale
        guard scale > 0 else { return nil }
        let imageRect = CGRect(
            x: (window.minX + scrollView.contentOffset.x) / scale,
            y: (window.minY + scrollView.contentOffset.y) / scale,
            width: window.width / scale,
            height: window.height / scale
        )
        let bounds = CGRect(origin: .zero, size: sourceImage.size)
        let clamped = imageRect.intersection(bounds)
        guard clamped.width > 1, clamped.height > 1 else { return nil }
        return clamped
    }

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
        scrollView.zoomScale = clampedZoom
        scrollView.contentOffset = CGPoint(
            x: clamped.origin.x * clampedZoom - scrollView.contentInset.left,
            y: clamped.origin.y * clampedZoom - scrollView.contentInset.top
        )
        return true
    }
}

private extension CGRect {
    /// True when every edge is within `tolerance` points — Auto Layout can re-derive a
    /// frame that differs from the last pass only by float noise.
    func isClose(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        guard !isNull, !other.isNull else { return isNull && other.isNull }
        return abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
