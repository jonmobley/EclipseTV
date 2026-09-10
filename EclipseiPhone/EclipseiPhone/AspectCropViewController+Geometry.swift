//
//  AspectCropViewController+Geometry.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Layout the scroll metrics were last configured for.
///
/// The cropper is presented over full screen, so its safe-area insets settle *after*
/// the first layout pass and the crop window moves at least once on the way in.
/// Configuring the metrics exactly once left the insets and zoom limits describing a
/// window that no longer existed.
struct AspectCropScrollGeometry: Equatable {
    let cropFrame: CGRect
    let scrollFrame: CGRect
}

// MARK: - Crop Frame Geometry

extension AspectCropViewController {

    /// Centers the white crop window in the scroll view at `targetAspect`.
    ///
    /// Set as a frame rather than through constraints: the metrics below read the
    /// window straight back, and re-activating constraints only takes effect after
    /// another layout pass — one that would re-enter this update halfway through it.
    func layoutCropFrame() {
        let maxW = scrollView.bounds.width - 32
        let maxH = scrollView.bounds.height - 32
        guard maxW > 0, maxH > 0 else { return }

        var cropW = maxW
        var cropH = cropW / targetAspect
        if cropH > maxH {
            cropH = maxH
            cropW = cropH * targetAspect
        }

        cropFrameView.frame = CGRect(
            x: scrollView.frame.midX - cropW / 2,
            y: scrollView.frame.midY - cropH / 2,
            width: cropW,
            height: cropH
        )
    }

    /// Re-applies zoom limits, insets, and position for the current layout.
    ///
    /// - Parameter framed: Region shown inside the crop window before this layout pass,
    ///   so the user's framing survives a resize. Nil on the first pass, where
    ///   `initialCropRect` (or a centered crop) picks the opening position.
    func updateScrollMetrics(restoring framed: CGRect?) {
        let crop = cropFrameView.frame
        let imageSize = sourceImage.size
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              crop.width > 1, crop.height > 1,
              imageSize.width > 1, imageSize.height > 1 else { return }
        let geometry = AspectCropScrollGeometry(
            cropFrame: crop,
            scrollFrame: scrollView.frame
        )
        guard geometry != configuredGeometry else { return }
        let isFirstPass = configuredGeometry == nil
        configuredGeometry = geometry

        if isFirstPass {
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize
        }

        let minZoom = max(crop.width / imageSize.width, crop.height / imageSize.height)
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = max(minZoom * 4, minZoom + 0.01)

        let window = cropWindowInScrollFrame()
        scrollView.contentInset = UIEdgeInsets(
            top: window.minY,
            left: window.minX,
            bottom: scrollView.bounds.height - window.maxY,
            right: scrollView.bounds.width - window.maxX
        )

        let requested = (isFirstPass ? initialCropRect : framed) ?? centeredCropRect()
        if !applyCropRect(atTargetAspect(requested), cropFrame: crop) {
            _ = applyCropRect(centeredCropRect(), cropFrame: crop)
        }
    }

    /// Returns the editor to the opening framing — the photo fitted and centered in the
    /// crop window — without leaving the editor or touching what is stored. Nothing is
    /// saved until the user taps Save, so Cancel after a Reset still keeps the old framing.
    func resetToDefaultFraming(animated: Bool) {
        let crop = cropFrameView.frame
        guard configuredGeometry != nil, crop.width > 1, crop.height > 1 else { return }
        let apply = { _ = self.applyCropRect(self.centeredCropRect(), cropFrame: crop) }
        guard animated else {
            apply()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: apply)
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

    /// Visible crop frame mapped into source-image point space, kept in bounds.
    ///
    /// Always the display aspect: the white box is `targetAspect`, so a save must be
    /// too. A thin strip cannot be stored even if the raw mapping is slightly off.
    func visibleCropRectInImage() -> CGRect? {
        guard let raw = rawCropRectInImage() else { return nil }
        return clampedToImage(atTargetAspect(raw))
    }

    // MARK: - Mapping

    /// Crop window relative to the scroll view's frame, independent of scroll position.
    ///
    /// `cropFrameView` and `scrollView` are siblings in `view`, so their frames share a
    /// coordinate space and the offset is a plain subtraction.
    func cropWindowInScrollFrame() -> CGRect {
        cropFrameView.frame.offsetBy(
            dx: -scrollView.frame.minX,
            dy: -scrollView.frame.minY
        )
    }

    /// Crop window in source-image point space, before it is kept in bounds.
    ///
    /// Built from `contentOffset` and the zoom view's frame rather than `UIView.convert`.
    /// Two things are measured instead of assumed: the zoom is the ratio of the zoom
    /// view's frame to its bounds (what is actually rendered, whatever `zoomScale` says),
    /// and the photo is mapped through the rectangle `.scaleAspectFit` draws it in, so a
    /// zoom view whose bounds are not exactly the image's shape still maps correctly.
    func rawCropRectInImage() -> CGRect? {
        let bounds = imageView.bounds
        let frame = imageView.frame
        guard bounds.width > 0, bounds.height > 0,
              frame.width > 0, frame.height > 0 else { return nil }
        let zoom = frame.width / bounds.width
        guard let drawn = drawnImageRectInBounds(), zoom > 0 else { return nil }
        let size = sourceImage.size
        let window = cropWindowInScrollFrame()
        let origin = CGPoint(
            x: scrollView.contentOffset.x + window.minX,
            y: scrollView.contentOffset.y + window.minY
        )
        let inBounds = CGRect(
            x: bounds.minX + (origin.x - frame.minX) / zoom,
            y: bounds.minY + (origin.y - frame.minY) / zoom,
            width: window.width / zoom,
            height: window.height / zoom
        )
        return CGRect(
            x: (inBounds.minX - drawn.minX) * size.width / drawn.width,
            y: (inBounds.minY - drawn.minY) * size.height / drawn.height,
            width: inBounds.width * size.width / drawn.width,
            height: inBounds.height * size.height / drawn.height
        )
    }

    /// Where `.scaleAspectFit` draws the photo inside the zoom view's bounds.
    ///
    /// Equal to the bounds when they are the image's shape (the normal case).
    func drawnImageRectInBounds() -> CGRect? {
        let bounds = imageView.bounds
        let size = sourceImage.size
        guard bounds.width > 0, bounds.height > 0,
              size.width > 0, size.height > 0 else { return nil }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let drawnSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - drawnSize.width / 2,
            y: bounds.midY - drawnSize.height / 2,
            width: drawnSize.width,
            height: drawnSize.height
        )
    }

    /// Moves `rect` inside the image without changing its shape.
    ///
    /// Trimming the overhanging edge instead — what `intersection(_:)` does — turns a
    /// crop window that hangs off the photo into a thin strip, and that strip is what
    /// gets saved as the framing.
    private func clampedToImage(_ rect: CGRect) -> CGRect? {
        MediaCropGeometry.containedIn(rect, sourceImage.size)
    }

    /// Grows `rect` about its center to `targetAspect`.
    ///
    /// The crop window is always the display aspect, so a stored framing that isn't
    /// (an older save, or a Display Mode change since) reopens as the region around
    /// what it used to show instead of as its own odd shape.
    private func atTargetAspect(_ rect: CGRect) -> CGRect {
        MediaCropGeometry.atAspect(rect, targetAspect)
    }

    /// Largest `targetAspect` rect that fits the image, centered — the opening framing.
    private func centeredCropRect() -> CGRect {
        let size = sourceImage.size
        var width = size.width
        var height = width / targetAspect
        if height > size.height {
            height = size.height
            width = height * targetAspect
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Zooms and scrolls so `rect` fills the crop window. Returns false when the rect
    /// is unusable and the caller should fall back to a centered crop.
    private func applyCropRect(_ rect: CGRect, cropFrame: CGRect) -> Bool {
        guard let clamped = clampedToImage(rect) else { return false }
        let fitting = max(
            cropFrame.width / clamped.width,
            cropFrame.height / clamped.height
        )
        let zoom = min(
            max(fitting, scrollView.minimumZoomScale),
            scrollView.maximumZoomScale
        )
        scrollView.zoomScale = zoom
        let inset = scrollView.contentInset
        scrollView.contentOffset = CGPoint(
            x: clamped.minX * zoom - inset.left,
            y: clamped.minY * zoom - inset.top
        )
        // Measured rather than trusted: the offset above assumes the zoom view sits at
        // the content origin, and the scroll view may clamp what it is given.
        for _ in 0..<2 {
            scrollView.layoutIfNeeded()
            guard let shown = rawCropRectInImage() else { break }
            let dx = (clamped.midX - shown.midX) * zoom
            let dy = (clamped.midY - shown.midY) * zoom
            guard abs(dx) > 0.5 || abs(dy) > 0.5 else { break }
            scrollView.contentOffset = CGPoint(
                x: scrollView.contentOffset.x + dx,
                y: scrollView.contentOffset.y + dy
            )
        }
        return true
    }
}
