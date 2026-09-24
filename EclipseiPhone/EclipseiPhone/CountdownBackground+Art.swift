//
//  CountdownBackground+Art.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Tile & Menu Art

@MainActor
extension CountdownBackground {

    /// Saved background for `item`, preferring the store over a possibly stale
    /// grid-row snapshot.
    static func resolved(for item: ShowCountdown) -> CountdownBackground {
        CountdownStore.shared.countdown(id: item.id)?.background ?? item.background
    }

    /// Poster that stands in for this background on tiles and menu rows.
    ///
    /// Nil for black, and for a referenced item whose thumbnail is not cached yet —
    /// callers fall back to the flat card or a glyph, the same as media tiles do.
    var tileImage: UIImage? {
        switch self {
        case .black:
            return nil
        case .screensaver:
            return ScreensaverStore.poster
        case .background:
            return LogoStore.shared.image
        case .libraryItem(let id):
            return TVLibraryStore.shared.thumbnail(for: id)
        }
    }

    /// Row image for the ⋯ → Background menu: a rounded thumbnail when one exists,
    /// otherwise `fallbackSymbol`.
    func menuImage(fallbackSymbol: String) -> UIImage? {
        guard let art = tileImage else {
            return UIImage(systemName: fallbackSymbol)
        }
        return CountdownBackgroundMenuIcon.render(art)
    }
}

// MARK: - Menu Icon

/// Renders library thumbnails at menu-row size for the Background picker.
///
/// `UIAction` draws its image at native point size, so a raw thumbnail would blow
/// the row up; a fixed square keeps every row aligned whatever the source aspect.
enum CountdownBackgroundMenuIcon {

    /// Point size of the rendered square.
    static let side: CGFloat = 28
    /// Corner radius matching the grid card at menu scale.
    static let cornerRadius: CGFloat = 6

    /// Aspect-fills `image` into a rounded square, kept in original color.
    static func render(_ image: UIImage) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let rendered = renderer.image { _ in
            UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).addClip()
            image.draw(in: aspectFillRect(for: image.size, in: bounds))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }

    /// Largest rect of `size`'s aspect that covers `bounds`, centered.
    static func aspectFillRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
