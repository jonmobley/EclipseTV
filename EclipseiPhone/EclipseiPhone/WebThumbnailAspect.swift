//
//  WebThumbnailAspect.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Fits website tile art to the active Display Mode panel (16:9 or 9:16).
enum WebThumbnailAspect {

    /// Target width ÷ height for website tiles and live output.
    static var displayAspectRatio: CGFloat {
        ExternalOutputSettings.orientation.aspectRatio
    }

    /// Crops a page snapshot to Display Mode aspect.
    ///
    /// Tall captures keep the top (matching the TV viewport); wide ones crop
    /// the sides. Near-matches are returned unchanged.
    static func croppedToDisplayAspect(_ image: UIImage) -> UIImage {
        let target = displayAspectRatio
        let size = image.size
        guard size.width > 1, size.height > 1 else { return image }
        let imageAspect = size.width / size.height
        guard abs(imageAspect - target) / target >= 0.02 else { return image }

        let crop: CGRect
        if imageAspect > target {
            let width = size.height * target
            crop = CGRect(
                x: (size.width - width) / 2,
                y: 0,
                width: width,
                height: size.height
            )
        } else {
            let height = size.width / target
            crop = CGRect(x: 0, y: 0, width: size.width, height: height)
        }
        return render(image, in: crop.size) { image.draw(at: CGPoint(x: -crop.minX, y: -crop.minY)) }
    }

    /// Centers a favicon (or other square art) inside a Display Mode frame.
    static func letterboxedInDisplayAspect(_ image: UIImage) -> UIImage {
        let target = displayAspectRatio
        let shortSide: CGFloat = 256
        let canvas: CGSize
        if target >= 1 {
            canvas = CGSize(width: shortSide * target, height: shortSide)
        } else {
            canvas = CGSize(width: shortSide, height: shortSide / target)
        }
        let maxIcon = min(canvas.width, canvas.height) * 0.42
        let iconSide = min(maxIcon, max(image.size.width, image.size.height))
        let iconRect = CGRect(
            x: (canvas.width - iconSide) / 2,
            y: (canvas.height - iconSide) / 2,
            width: iconSide,
            height: iconSide
        )
        return render(image, in: canvas) { image.draw(in: iconRect) }
    }

    // MARK: - Private

    private static func render(
        _ image: UIImage,
        in size: CGSize,
        draw: () -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw()
        }
    }
}
