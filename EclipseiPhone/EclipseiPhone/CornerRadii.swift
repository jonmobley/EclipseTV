//
//  CornerRadii.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Shared corner-radius tokens (HIG continuous squircle).
enum CornerRadii {
    /// Compact chips and small badges.
    static let compact: CGFloat = 8
    /// Standard cards and controls.
    static let standard: CGFloat = 12
    /// Home tiles and medium cards.
    static let card: CGFloat = 16
    /// Large hero / drawer surfaces.
    static let large: CGFloat = 22
}

extension CALayer {

    /// Applies a continuous corner curve at the given radius.
    func applyContinuousCorner(radius: CGFloat) {
        cornerRadius = radius
        cornerCurve = .continuous
    }
}
