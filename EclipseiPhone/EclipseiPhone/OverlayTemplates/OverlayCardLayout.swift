//
//  OverlayCardLayout.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Shared geometry for positioning a card overlay inside a 16:9
//               content frame. Resolves either the operator's free placement or
//               the corner dock into a concrete center, and keeps the card inside
//               the frame. Used by both the read-only external display card and
//               the editable preview card so every surface agrees.
//  Thread Safety: Pure functions on value types - safe on any thread.
//

import SwiftUI

// MARK: - OverlayCardLayout

/// Positioning helpers shared by `PlacedCardOverlay` and `EditableCardOverlay`.
enum OverlayCardLayout {

    /// Corner inset at the 1080p reference scale, matching the cast renderer's
    /// `referenceMargin` and the historical `48 * scale` SwiftUI padding.
    static let referenceMargin: CGFloat = 48

    /// Reference height the card metrics are tuned for (1080p).
    static let referenceHeight: CGFloat = 1080

    /// Scale factor mapping 1080p card metrics onto `contentFrame`.
    static func containerScale(_ contentFrame: CGRect) -> CGFloat {
        contentFrame.height / referenceHeight
    }

    // MARK: - Placement Resolution

    /// The placement to lay the card out with: the stored free placement, or a
    /// derived placement that reproduces the corner dock for a card of
    /// `cardSize`.
    ///
    /// - Parameter cardSize: Card size in `contentFrame` points (already mapped
    ///   by `containerScale`). Do not pass raw 1080p / scale-1 metrics.
    static func basePlacement(config: OverlayCardConfig,
                              cardSize: CGSize,
                              contentFrame: CGRect) -> OverlayCardPlacement {
        if let placement = config.placement { return placement.clamped() }
        let center = dockedCenter(corner: config.corner,
                                  cardSize: cardSize, contentFrame: contentFrame)
        return OverlayCardPlacement(centerX: center.x, centerY: center.y, scale: 1)
    }

    /// Maps a 1080p (`OverlayCardView` scale 1) size onto `contentFrame`.
    static func displayedSize(
        intrinsicSize: CGSize,
        in contentFrame: CGRect
    ) -> CGSize {
        let scale = containerScale(contentFrame)
        return CGSize(
            width: intrinsicSize.width * scale,
            height: intrinsicSize.height * scale
        )
    }

    /// Normalized center (`0...1` in `contentFrame`) that docks a card of
    /// `cardSize` (in frame points) to `corner` with the standard margin.
    static func dockedCenter(corner: OverlayCorner,
                             cardSize: CGSize,
                             contentFrame: CGRect) -> CGPoint {
        let margin = referenceMargin * containerScale(contentFrame)
        let halfW = cardSize.width / 2
        let halfH = cardSize.height / 2
        let x: CGFloat
        switch corner {
        case .topLeading, .bottomLeading: x = contentFrame.minX + margin + halfW
        case .topTrailing, .bottomTrailing: x = contentFrame.maxX - margin - halfW
        }
        let y: CGFloat
        switch corner {
        case .topLeading, .topTrailing: y = contentFrame.minY + margin + halfH
        case .bottomLeading, .bottomTrailing: y = contentFrame.maxY - margin - halfH
        }
        return normalized(CGPoint(x: x, y: y), in: contentFrame)
    }

    // MARK: - Coordinate Conversion

    /// Converts a container-space point into a `0...1` fraction of `frame`.
    static func normalized(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return point }
        return CGPoint(x: (point.x - frame.minX) / frame.width,
                       y: (point.y - frame.minY) / frame.height)
    }

    /// Converts a `0...1` fraction of `frame` back into a container-space point.
    static func denormalized(_ fraction: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + fraction.x * frame.width,
                y: frame.minY + fraction.y * frame.height)
    }

    // MARK: - Clamping

    /// Constrains a card center so a card of `size` keeps its edges inside
    /// `contentFrame`; if the card is larger than the frame on an axis it is
    /// centered on that axis.
    static func clampedCenter(_ center: CGPoint,
                              cardSize size: CGSize,
                              in contentFrame: CGRect) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        return CGPoint(
            x: clamp(center.x,
                     lower: contentFrame.minX + halfW, upper: contentFrame.maxX - halfW),
            y: clamp(center.y,
                     lower: contentFrame.minY + halfH, upper: contentFrame.maxY - halfH)
        )
    }

    private static func clamp(_ value: CGFloat,
                              lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(upper, max(lower, value))
    }
}
