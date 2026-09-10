//
//  AspectCropViewController+Diagnostics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Save Trace

extension AspectCropViewController {

    /// Dumps everything the Save mapping reads, plus the rect it produced.
    ///
    /// `convert` is the same window mapped through `UIView.convert` instead of the
    /// scroll arithmetic; the two agreeing (or not) is the point of logging both.
    func logSave(saved: CGRect?) {
        let scroll = scrollView
        let zoomView = imageView
        let raw = rawCropRectInImage().map(ReframeLog.rect) ?? "nil"
        let converted = convertedCropRectInImage().map(ReframeLog.rect) ?? "nil"
        let drawn = drawnImageRectInBounds().map(ReframeLog.rect) ?? "nil"
        let unit = saved.map {
            ReframeLog.framing(MediaFraming(rect: $0, in: sourceImage.size))
        } ?? "none"
        let transform = zoomView.transform
        ReframeLog.emit("""
        [Reframe] SAVE target=\(ReframeLog.fmt(targetAspect)) \
        vertical=\(ExternalOutputSettings.isVerticalMode)
          image \(ReframeLog.image(sourceImage))
          view bounds \(ReframeLog.rect(view.bounds)) safe \(ReframeLog.insets(view.safeAreaInsets))
          scroll frame \(ReframeLog.rect(scroll.frame)) offset \
        (\(ReframeLog.fmt(scroll.contentOffset.x)),\(ReframeLog.fmt(scroll.contentOffset.y))) \
        inset \(ReframeLog.insets(scroll.contentInset)) \
        adjusted \(ReframeLog.insets(scroll.adjustedContentInset)) \
        contentSize \(ReframeLog.size(scroll.contentSize)) \
        zoom \(ReframeLog.fmt(scroll.zoomScale)) \
        [\(ReframeLog.fmt(scroll.minimumZoomScale)), \(ReframeLog.fmt(scroll.maximumZoomScale))]
          crop frame \(ReframeLog.rect(cropFrameView.frame)) \
        window \(ReframeLog.rect(cropWindowInScrollFrame()))
          zoomView frame \(ReframeLog.rect(zoomView.frame)) \
        bounds \(ReframeLog.rect(zoomView.bounds)) \
        transform (\(ReframeLog.fmt(transform.a)),\(ReframeLog.fmt(transform.d))) \
        drawn \(drawn)
          raw \(raw)
          convert \(converted)
          saved \(saved.map(ReframeLog.rect) ?? "nil") \(unit)
        """)
    }

    /// The window mapped with `UIView.convert`, as a cross-check on `rawCropRectInImage`.
    private func convertedCropRectInImage() -> CGRect? {
        guard let drawn = drawnImageRectInBounds() else { return nil }
        let size = sourceImage.size
        let inBounds = imageView.convert(cropFrameView.bounds, from: cropFrameView)
        return CGRect(
            x: (inBounds.minX - drawn.minX) * size.width / drawn.width,
            y: (inBounds.minY - drawn.minY) * size.height / drawn.height,
            width: inBounds.width * size.width / drawn.width,
            height: inBounds.height * size.height / drawn.height
        )
    }
}
