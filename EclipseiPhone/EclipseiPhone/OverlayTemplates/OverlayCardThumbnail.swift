//
//  OverlayCardThumbnail.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name)
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Renders a program-aspect thumbnail of a template card on a
//               dark background, placed where it sits on output. Used by the
//               Show grid tile and the template picker.
//  Thread Safety: Main actor only (SwiftUI `ImageRenderer`).
//

import UIKit

// MARK: - OverlayCardThumbnail

@MainActor
enum OverlayCardThumbnail {

    // MARK: - Constants

    /// Thumbnail pixels (16:9). Twice the Mac's 480-wide slot so the card,
    /// which rasterizes at 1 pixel per point, stays sharp on Retina tiles.
    static let size = CGSize(width: 960, height: 540)
    /// Slot background (the Mac's 0.08 white).
    private static let backgroundWhite: CGFloat = 0.08

    private static var cache: [String: UIImage] = [:]

    // MARK: - Public Interface

    /// Renders (or returns the cached) thumbnail for `config`.
    ///
    /// - Parameter config: The card configuration to preview.
    /// - Returns: A thumbnail image, or nil if rasterization fails.
    static func image(for config: OverlayCardConfig) -> UIImage? {
        let key = config.syncJSONString() ?? ""
        if let cached = cache[key] { return cached }
        guard let image = render(config, in: size) else { return nil }
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }

    /// Renders `config` on a dark program frame of `frameSize` (uncached).
    ///
    /// - Parameters:
    ///   - config: The card configuration to draw.
    ///   - frameSize: Program frame size; 1920×1080 gives a full-size still.
    /// - Returns: The image, or nil if rasterization fails.
    static func render(_ config: OverlayCardConfig, in frameSize: CGSize) -> UIImage? {
        let slot = CGRect(origin: .zero, size: frameSize)
        let baseScale = frameSize.height / OverlayCardLayout.referenceHeight
        let cardScale = baseScale * (config.placement?.scale ?? 1)
        guard let card = OverlayCardView.rasterize(config: config, scale: cardScale) else {
            return nil
        }
        let pad = OverlayCardView.rasterPadding(scale: cardScale)
        let plate = CGSize(width: card.size.width - pad * 2, height: card.size.height - pad * 2)
        let base = OverlayCardLayout.basePlacement(config: config, cardSize: plate, contentFrame: slot)
        let center = OverlayCardLayout.clampedCenter(
            OverlayCardLayout.denormalized(CGPoint(x: base.centerX, y: base.centerY), in: slot),
            cardSize: plate,
            in: slot
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: frameSize, format: format).image { context in
            UIColor(white: backgroundWhite, alpha: 1).setFill()
            context.fill(slot)
            card.draw(at: CGPoint(
                x: center.x - plate.width / 2 - pad,
                y: center.y - plate.height / 2 - pad
            ))
        }
    }
}
