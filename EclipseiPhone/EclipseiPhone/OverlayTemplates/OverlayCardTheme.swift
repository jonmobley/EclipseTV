//
//  OverlayCardTheme.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Shared design tokens for card overlays: the four-step type
//               scale, spacing, plate limits, and the drop shadow. Every card
//               layout reads its metrics from here so the 27 templates share
//               one rhythm; colors, fonts, and radii come from `OverlayCardLook`.
//  Thread Safety: Value types / static constants - no shared mutable state.
//

import SwiftUI

// MARK: - OverlayCardTheme

/// Design tokens for template-driven card overlays at the 1080p reference.
///
/// Layouts multiply every token by their `scale` so the same values render
/// proportionally on the preview, the external display, and the cast canvas.
enum OverlayCardTheme {

    // MARK: - Type Scale

    /// Type scale at the 1080p reference. Four steps: label, secondary, title,
    /// display. Nothing on air renders below `label`.
    enum TypeScale {
        static let label: CGFloat = 28
        static let secondary: CGFloat = 34
        static let title: CGFloat = 48
        static let display: CGFloat = 72

        /// Letter spacing for uppercase eyebrows and labels.
        static let labelTracking: CGFloat = 1.6

        /// Label size that tracks the operator's subtitle size, never below
        /// the smallest legible on-air size.
        static func label(for style: OverlayCardStyle) -> CGFloat {
            max(22, style.subtitleSize * (label / secondary))
        }

        /// Display size (scores, big numbers) that tracks the title size.
        static func display(for style: OverlayCardStyle) -> CGFloat {
            style.titleSize * (display / title)
        }
    }

    // MARK: - Spacing

    /// Spacing tokens on an 8 px grid at the 1080p reference.
    enum Space {
        static let unit: CGFloat = 8
        /// Horizontal plate padding.
        static let padH: CGFloat = 40
        /// Vertical plate padding.
        static let padV: CGFloat = 28
        /// Gap between lines in one text block.
        static let lineGap: CGFloat = 6
        /// Gap between an eyebrow and the block below it.
        static let stackGap: CGFloat = 12
        /// Gap between an inline icon and the text stack.
        static let inlineGap: CGFloat = 24
        /// Width of the accent spine on the leading edge.
        static let spine: CGFloat = 6
        /// Narrowest plate for lower thirds so short names still read as a bar.
        static let minPlateWidth: CGFloat = 440
        /// Widest plate; long text wraps past this.
        static let maxPlateWidth: CGFloat = 800
        /// Distance from the frame edge when a card is docked to a corner.
        static let safeMargin: CGFloat = 48
    }

    // MARK: - Shadow

    /// The one drop shadow every plate casts.
    enum Shadow {
        static let opacity: Double = 0.42
        static let radius: CGFloat = 22
        static let offsetY: CGFloat = 8

        /// Transparent border a raster needs around the plate so the shadow is
        /// not clipped when the card is drawn into a bitmap.
        static var padding: CGFloat { radius * 2 + offsetY }
    }

    // MARK: - Opacity

    /// Plate opacity for the Glass Strip lower third, the one template that
    /// is meant to show the picture through it.
    static let opacityGlass: Double = 0.72
}
