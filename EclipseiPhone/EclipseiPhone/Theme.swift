//
//  Theme.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Shared colour tokens. Radii live in `CornerRadii`, type in `Typography`.
///
/// The app runs in Dark appearance, so these are fixed greys rather than
/// semantic system colours; naming them by role keeps sibling surfaces from
/// drifting apart by a few percent of white.
extension UIColor {

    /// App accent for tinted chrome, selection, and primary buttons. Reads the
    /// `AccentColor` asset so code-side chrome matches the global tint.
    static let accent: UIColor = UIColor(named: "AccentColor") ?? .systemBlue

    /// Fill behind media while it loads, and behind hero / overlay placeholders.
    static let mediaPlaceholder = UIColor(white: 0.12, alpha: 1)

    /// Fill for special (non-media) tiles and ribbon cues in the grids.
    static let specialTile = UIColor(white: 0.16, alpha: 1)
}
