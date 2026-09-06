//
//  ZoomableImageView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Pinch, pan, and double-tap zoom around a still, like the system Photos app.
///
/// Scale math lives in `ZoomableImageLayout`.
final class ZoomableImageView: UIView, UIScrollViewDelegate {

    /// How the image sits when zoomed all the way out.
    enum MinimumFit: Equatable {
        /// Entire image visible; extra space is letterboxed (Photos).
        case contain
        /// Image covers the view; overflow is clipped (Display Mode panel).
        case cover
    }

    /// Resting scale: contain (fit) or cover (fill).
    var minimumFit: MinimumFit = .contain {
        didSet {
            guard oldValue != minimumFit else { return }
            resetToMinimumScale()
        }
    }

    /// Still to zoom. Updating this resets zoom to the fitted scale.
    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            resetToMinimumScale()
        }
    }

    /// Fired when the image crosses between fitted and zoomed.
    var onZoomedChanged: ((Bool) -> Void)?

    /// True when the user has zoomed in past the fitted scale.
    var isZoomed: Bool {
        ZoomableImageLayout.isZoomed(
            zoomScale: scrollView.zoomScale,
            minimumZoomScale: scrollView.minimumZoomScale
        )
    }

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var lastLayoutSize: CGSize = .zero
    private var reportedZoomed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScrollView()
        setupDoubleTap()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.size.width > 0, bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        // Rotation lands here: refit rather than carry a zoom framed for the old axis.
        // Rescale only — re-framing would move the zoom scale twice, and see
        // `applyMinimumScale` for why a turn must move it exactly once.
        applyMinimumScale()
    }

    /// Returns to the fitted scale.
    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        snapFittedContentSize()
        applyLetterboxInsets()
        if animated {
            centerCoverOffsetIfNeeded()
        } else {
            centerContent()
        }
        updatePanningEnabled()
        notifyZoomedIfNeeded(force: true)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        applyLetterboxInsets()
        updatePanningEnabled()
        notifyZoomedIfNeeded()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        onZoomedChanged?(true)
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        snapFittedContentSize()
        applyLetterboxInsets()
        centerCoverOffsetIfNeeded()
        updatePanningEnabled()
        notifyZoomedIfNeeded(force: true)
    }

    // MARK: - Setup

    private func setupScrollView() {
        backgroundColor = .black
        clipsToBounds = true
        scrollView.backgroundColor = .black
        scrollView.clipsToBounds = true
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        addSubview(scrollView)
        scrollView.addSubview(imageView)
    }

    private func setupDoubleTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(tap)
    }

    // MARK: - Zoom

    /// Re-frames the image at its natural size, then zooms out to the fitted scale.
    ///
    /// For a new image or fit mode. A bounds change calls `applyMinimumScale` alone.
    private func resetToMinimumScale() {
        reframeAtNaturalSize()
        applyMinimumScale()
    }

    /// Restores the identity-scaled frame that the fitted scale is derived from.
    private func reframeAtNaturalSize() {
        let imageSize = imageView.image?.size ?? .zero
        // UIScrollView zooms by transforming `imageView`, and `frame` is undefined on a
        // transformed view: UIKit derives bounds by dividing through the transform, so
        // re-framing at zoomScale 0.2 inflated the image 5x on every rotation and left
        // `minimumZoomScale` (computed from the natural size) unable to fit it again.
        // Drop to identity before touching the frame.
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize
    }

    /// Zooms out to the scale that fits (or covers) the current bounds.
    ///
    /// Moves `zoomScale` exactly once. UIKit runs layout inside the rotation animation,
    /// so every assignment leaves an additive transform animation on the image layer,
    /// and additive deltas *multiply*: two of them trace a curve that bulges far past
    /// both endpoints instead of easing between the two fitted scales.
    private func applyMinimumScale() {
        let minScale = ZoomableImageLayout.minimumScale(
            imageSize: imageView.image?.size ?? .zero,
            boundsSize: scrollView.bounds.size,
            fit: minimumFit
        )
        let maxScale = minScale * ZoomableImageLayout.maxZoomMultiplier
        // Widen before narrowing: clamping a zoomed-in image against the new limits
        // would be a second move of the scale.
        scrollView.minimumZoomScale = min(minScale, scrollView.zoomScale)
        scrollView.maximumZoomScale = max(maxScale, scrollView.zoomScale)
        scrollView.zoomScale = minScale
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        snapFittedContentSize()
        applyLetterboxInsets()
        centerContent()
        updatePanningEnabled()
        notifyZoomedIfNeeded(force: true)
    }

    /// At the fitted scale, pins content that only overshoots the bounds by float error.
    private func snapFittedContentSize() {
        guard !isZoomed else { return }
        scrollView.contentSize = ZoomableImageLayout.snappedContentSize(
            scrollView.contentSize,
            boundsSize: scrollView.bounds.size
        )
    }

    /// Centers the content at the resting scale (letterboxed or overflowing).
    private func centerContent() {
        scrollView.contentOffset = ZoomableImageLayout.centeredContentOffset(
            contentSize: scrollView.contentSize,
            boundsSize: scrollView.bounds.size
        )
    }

    private func applyLetterboxInsets() {
        let boundsSize = scrollView.bounds.size
        let content = scrollView.contentSize
        let insetX = max((boundsSize.width - content.width) / 2, 0)
        let insetY = max((boundsSize.height - content.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: insetY, left: insetX, bottom: insetY, right: insetX
        )
    }

    private func centerCoverOffsetIfNeeded() {
        guard minimumFit == .cover, !isZoomed else { return }
        let boundsSize = scrollView.bounds.size
        let content = scrollView.contentSize
        let offsetX = max((content.width - boundsSize.width) / 2, 0)
        let offsetY = max((content.height - boundsSize.height) / 2, 0)
        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    private func updatePanningEnabled() {
        switch minimumFit {
        case .contain:
            scrollView.isScrollEnabled = true
        case .cover:
            scrollView.isScrollEnabled = isZoomed
        }
    }

    private func notifyZoomedIfNeeded(force: Bool = false) {
        let zoomed = isZoomed
        guard force || zoomed != reportedZoomed else { return }
        reportedZoomed = zoomed
        onZoomedChanged?(zoomed)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        if isZoomed {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            zoomIn(around: gesture.location(in: imageView))
        }
    }

    private func zoomIn(around point: CGPoint) {
        let scale = min(
            scrollView.maximumZoomScale,
            scrollView.minimumZoomScale * ZoomableImageLayout.doubleTapMultiplier
        )
        let size = scrollView.bounds.size
        let width = size.width / scale
        let height = size.height / scale
        let rect = CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
        scrollView.zoom(to: rect, animated: true)
    }
}
