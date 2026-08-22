//
//  ZoomableImageView.swift
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
}

/// Pinch, pan, and double-tap zoom around a still, like the system Photos app.
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
            updateZoomScales(forceMinimum: true)
        }
    }

    /// Still to zoom. Updating this resets zoom to the fitted scale.
    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            updateZoomScales(forceMinimum: true)
        }
    }

    /// Fired when the image crosses between fitted and zoomed.
    var onZoomedChanged: ((Bool) -> Void)?

    /// True when the user has zoomed in past the fitted scale.
    var isZoomed: Bool {
        scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
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
        updateZoomScales(forceMinimum: true)
    }

    /// Returns to the fitted scale.
    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        applyLetterboxInsets()
        centerCoverOffsetIfNeeded()
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

    private func updateZoomScales(forceMinimum: Bool) {
        let boundsSize = scrollView.bounds.size
        let imageSize = imageView.image?.size ?? .zero
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        let minScale = ZoomableImageLayout.minimumScale(
            imageSize: imageSize,
            boundsSize: boundsSize,
            fit: minimumFit
        )
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = minScale * ZoomableImageLayout.maxZoomMultiplier
        if forceMinimum {
            scrollView.zoomScale = minScale
        }
        applyLetterboxInsets()
        centerCoverOffsetIfNeeded()
        updatePanningEnabled()
        notifyZoomedIfNeeded(force: true)
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
