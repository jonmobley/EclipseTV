//
//  PreviewDismissGeometry.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Drag math for closing a fullscreen Preview by pulling it down like a drawer.
///
/// Split out from the transition so the feel can be tuned and tested without a
/// running gesture.
enum PreviewDismissGeometry {

    /// Downward drag, in points, that maps to a fully dismissed card.
    static let travel: CGFloat = 260
    /// Fraction of `travel` past which lifting the finger commits the dismissal.
    static let commitProgress: CGFloat = 0.28
    /// Vertical speed (pt/s) that commits on its own, so a flick closes from anywhere.
    static let commitVelocity: CGFloat = 900
    /// Scale the card shrinks to at full progress.
    static let minimumScale: CGFloat = 0.86
    /// Dim over the screen behind while the card is still at rest.
    static let restingDim: CGFloat = 0.45
    /// Share of sideways travel the card follows, so the drag reads as mostly vertical.
    static let horizontalDamping: CGFloat = 0.4
    /// Share of upward travel the card follows, as a rubber band against a closed lid.
    static let upwardResistance: CGFloat = 0.2
    /// Fraction of `travel` over which the corners round off.
    static let cornerRampProgress: CGFloat = 0.25

    /// Card offset for a raw gesture translation.
    ///
    /// Sideways motion is damped and upward motion resisted: the gesture only ever
    /// means "close", so off-axis travel is feedback rather than a second axis.
    static func cardOffset(for translation: CGPoint) -> CGPoint {
        CGPoint(
            x: translation.x * horizontalDamping,
            y: translation.y < 0 ? translation.y * upwardResistance : translation.y
        )
    }

    /// How far through the dismissal a vertical card offset sits, clamped to 0...1.
    static func progress(forVerticalOffset offset: CGFloat) -> CGFloat {
        clamped(offset / travel)
    }

    static func scale(at progress: CGFloat) -> CGFloat {
        1 - (1 - minimumScale) * clamped(progress)
    }

    /// Corners round off over the first stretch of the drag, so the card reads as a
    /// detached sheet almost immediately rather than easing into one at the very end.
    static func cornerRadius(at progress: CGFloat) -> CGFloat {
        CornerRadii.large * clamped(progress / cornerRampProgress)
    }

    /// The screen behind starts dimmed and lifts as the card clears it.
    static func dimAlpha(at progress: CGFloat) -> CGFloat {
        restingDim * (1 - clamped(progress))
    }

    /// Whether releasing here should close rather than spring back.
    ///
    /// Velocity outranks distance in both directions: a flick down closes from barely
    /// any travel, and a flick back up cancels even from past the distance threshold.
    static func shouldComplete(progress: CGFloat, verticalVelocity: CGFloat) -> Bool {
        if verticalVelocity >= commitVelocity { return true }
        if verticalVelocity <= -commitVelocity { return false }
        return progress >= commitProgress
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
