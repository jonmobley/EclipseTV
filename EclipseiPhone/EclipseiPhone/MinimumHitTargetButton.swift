//
//  MinimumHitTargetButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// `UIButton` that expands hit testing to at least 44×44 pt (HIG minimum).
///
/// Visual size can stay smaller via layout constraints; only the tappable
/// area grows. Prefer this for icon chrome that looks better at 28–36 pt.
final class MinimumHitTargetButton: UIButton {

    /// Minimum edge length for the expanded hit rect (Apple HIG).
    static let minimumEdge: CGFloat = 44

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let minEdge = Self.minimumEdge
        let dx = max(0, (minEdge - bounds.width) / 2)
        let dy = max(0, (minEdge - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}
