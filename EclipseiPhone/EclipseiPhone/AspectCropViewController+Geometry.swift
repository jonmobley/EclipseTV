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
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        let scaleW = crop.width / imageSize.width
        let scaleH = crop.height / imageSize.height
        let minZoom = max(scaleW, scaleH)
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = max(minZoom * 4, minZoom + 0.01)

        let cropInScroll = scrollView.convert(crop, from: view)
        scrollView.contentInset = UIEdgeInsets(
            top: cropInScroll.minY,
            left: cropInScroll.minX,
            bottom: scrollView.bounds.height - cropInScroll.maxY,
            right: scrollView.bounds.width - cropInScroll.maxX
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
    func visibleCropRectInImage() -> CGRect? {
        let cropInScroll = scrollView.convert(cropFrameView.frame, from: view)
        let scale = scrollView.zoomScale
        guard scale > 0 else { return nil }
        let imageRect = CGRect(
            x: (cropInScroll.origin.x + scrollView.contentOffset.x) / scale,
            y: (cropInScroll.origin.y + scrollView.contentOffset.y) / scale,
            width: cropInScroll.width / scale,
            height: cropInScroll.height / scale
        )
        let bounds = CGRect(origin: .zero, size: sourceImage.size)
        let clamped = imageRect.intersection(bounds)
        guard clamped.width > 1, clamped.height > 1 else { return nil }
        return clamped
    }

    // MARK: - Private

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
