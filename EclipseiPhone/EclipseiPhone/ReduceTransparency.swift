//
//  ReduceTransparency.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIVisualEffectView {

    /// Replaces blur with an opaque fill when Reduce Transparency is on (HIG).
    func applyReduceTransparencyFallback(opaqueFill: UIColor) {
        guard UIAccessibility.isReduceTransparencyEnabled else { return }
        effect = nil
        backgroundColor = opaqueFill
    }
}
