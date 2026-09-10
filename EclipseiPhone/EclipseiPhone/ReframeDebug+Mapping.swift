//
//  ReframeDebug+Mapping.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension ReframeDebug {

    /// Same convert the save path uses, but going through the scroll view first.
    static func convertViaScrollView(_ controller: AspectCropViewController) -> CGRect? {
        let imageView = controller.imageView
        let inScroll = controller.scrollView.convert(
            controller.cropFrameView.bounds, from: controller.cropFrameView
        )
        let inImage = imageView.convert(inScroll, from: controller.scrollView)
        return scaleToImage(inImage, imageView: imageView, size: controller.sourceImage.size)
    }

    /// contentOffset + crop window, independent of UIView.convert.
    static func arithmeticCrop(_ controller: AspectCropViewController) -> CGRect? {
        let scroll = controller.scrollView
        let zoom = scroll.zoomScale
        guard zoom > 0 else { return nil }
        let window = controller.cropFrameView.frame.offsetBy(
            dx: -scroll.frame.minX,
            dy: -scroll.frame.minY
        )
        let origin = CGPoint(
            x: scroll.contentOffset.x + window.minX,
            y: scroll.contentOffset.y + window.minY
        )
        let frame = controller.imageView.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        return CGRect(
            x: (origin.x - frame.minX) / zoom,
            y: (origin.y - frame.minY) / zoom,
            width: window.width / zoom,
            height: window.height / zoom
        )
    }

    /// Image frame in the controller's view, from scroll math rather than convert.
    static func screenCrop(_ controller: AspectCropViewController) -> CGRect? {
        let scroll = controller.scrollView
        let imageFrame = controller.imageView.frame.offsetBy(
            dx: -scroll.contentOffset.x + scroll.frame.minX,
            dy: -scroll.contentOffset.y + scroll.frame.minY
        )
        let crop = controller.cropFrameView.frame
        let size = controller.sourceImage.size
        guard imageFrame.width > 0, imageFrame.height > 0 else { return nil }
        return CGRect(
            x: (crop.minX - imageFrame.minX) * size.width / imageFrame.width,
            y: (crop.minY - imageFrame.minY) * size.height / imageFrame.height,
            width: crop.width * size.width / imageFrame.width,
            height: crop.height * size.height / imageFrame.height
        )
    }

    static func scaleToImage(
        _ rect: CGRect,
        imageView: UIImageView,
        size: CGSize
    ) -> CGRect? {
        let bounds = imageView.bounds
        guard bounds.width > 0, bounds.height > 0,
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(
            x: (rect.minX - bounds.minX) * size.width / bounds.width,
            y: (rect.minY - bounds.minY) * size.height / bounds.height,
            width: rect.width * size.width / bounds.width,
            height: rect.height * size.height / bounds.height
        )
    }

    static func imageViewLine(_ imageView: UIImageView) -> String {
        let a = fmt(imageView.transform.a)
        return "frame \(rect(imageView.frame)) bounds \(rect(imageView.bounds)) a=\(a)"
    }

    static func scrollLine(_ scrollView: UIScrollView) -> String {
        let zoom = fmt(scrollView.zoomScale)
        let minZoom = fmt(scrollView.minimumZoomScale)
        let ox = fmt(scrollView.contentOffset.x)
        let oy = fmt(scrollView.contentOffset.y)
        let insetT = fmt(scrollView.contentInset.top)
        let insetL = fmt(scrollView.contentInset.left)
        let content = rect(CGRect(origin: .zero, size: scrollView.contentSize))
        return """
        zoom \(zoom) (min \(minZoom)) off \(ox),\(oy) inset T\(insetT) L\(insetL) \
        content \(content) bounds \(rect(scrollView.bounds)) frame \(rect(scrollView.frame))
        """
    }

    static func windowLine(_ crop: UIView) -> String {
        "\(rect(crop.frame)) aspect \(aspect(crop.frame))"
    }

    static func describe(_ image: UIImage) -> String {
        let cg = image.cgImage
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 0
        return """
        \(fmt(image.size.width))×\(fmt(image.size.height)) @\(fmt(image.scale)) \
        cg \(cg?.width ?? 0)×\(cg?.height ?? 0) ori \(image.imageOrientation.rawValue) \
        \(fmt(aspect)):1
        """
    }

    static func rect(_ r: CGRect) -> String {
        String(
            format: "%.1f,%.1f %.1f×%.1f",
            r.minX, r.minY, r.width, r.height
        )
    }

    static func aspect(_ r: CGRect) -> String {
        guard r.height > 0.01 else { return "∞:1" }
        return "\(fmt(r.width / r.height)):1"
    }

    static func fmt(_ value: some BinaryFloatingPoint) -> String {
        String(format: "%.2f", Double(value))
    }
}
