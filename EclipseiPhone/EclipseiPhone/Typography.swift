//
//  Typography.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Dynamic Type helpers for the places a text style alone is the wrong shape —
/// weighted or monospaced numerals at a designed point size.
///
/// Pair every use with `adjustsFontForContentSizeCategory = true` on the label
/// (button configurations re-resolve on their own). Prefer
/// `preferredFont(forTextStyle:)` when the style already fits.
extension UIFont {

    /// A weighted system font at `size` that scales with the user's text size.
    ///
    /// - Parameter style: Text style whose scaling curve to follow.
    /// - Parameter maximumPointSize: Cap for chrome with fixed heights (buttons,
    ///   pills). Leave nil for body copy so it can grow freely.
    static func scaled(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        relativeTo style: UIFont.TextStyle = .body,
        maximumPointSize: CGFloat? = nil
    ) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: style)
        if let maximumPointSize {
            return metrics.scaledFont(for: base, maximumPointSize: maximumPointSize)
        }
        return metrics.scaledFont(for: base)
    }

    /// Monospaced-digit variant of `scaled` for clocks, counters, and timecodes.
    static func scaledMonospacedDigit(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        relativeTo style: UIFont.TextStyle = .body,
        maximumPointSize: CGFloat? = nil
    ) -> UIFont {
        let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: style)
        if let maximumPointSize {
            return metrics.scaledFont(for: base, maximumPointSize: maximumPointSize)
        }
        return metrics.scaledFont(for: base)
    }
}
