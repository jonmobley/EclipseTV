//
//  OverlayCardPlacement.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Free-placement geometry for template-driven card overlays. When
//               present it overrides the card's corner dock, storing a normalized
//               center and a scale multiplier so the same layout maps identically
//               onto the operator preview, the external display, and the
//               cast/recording canvas.
//  Thread Safety: Plain value type - safe to copy across threads.
//

import CoreGraphics

// MARK: - OverlayCardPlacement

/// Normalized position and size of a freely-placed card overlay.
///
/// Coordinates are relative to the 16:9 content frame so the layout is
/// resolution independent:
/// - `centerX` / `centerY`: card center, `0...1` (0 = left/top, 1 = right/bottom)
/// - `scale`: multiplier on the card's intrinsic size (the size it renders at
///   when docked to a corner). `1.0` is the natural size; larger zooms in.
struct OverlayCardPlacement: Codable, Equatable {

    // MARK: - Properties

    var centerX: CGFloat
    var centerY: CGFloat
    var scale: CGFloat

    // MARK: - Constants

    /// Smallest allowed scale (quarter of the intrinsic card size).
    static let minScale: CGFloat = 0.25

    /// Largest allowed scale (3x the intrinsic card size).
    static let maxScale: CGFloat = 3.0

    // MARK: - Clamping

    /// Returns a copy with the center confined to `0...1` and the scale clamped
    /// to `minScale...maxScale`.
    func clamped() -> OverlayCardPlacement {
        OverlayCardPlacement(
            centerX: min(1, max(0, centerX)),
            centerY: min(1, max(0, centerY)),
            scale: min(Self.maxScale, max(Self.minScale, scale))
        )
    }
}
