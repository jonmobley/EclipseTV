//
//  ShowCoverGradient.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Stable two-stop cover colors for Shows that have no thumbnail yet.
enum ShowCoverGradient {

    /// Returns a top→bottom color pair derived from `id` (same Show → same colors).
    static func colors(for id: UUID) -> [UIColor] {
        let pair = pairs[stableIndex(for: id) % pairs.count]
        return [pair.0, pair.1]
    }

    // MARK: - Private

    /// Saturated pairs that keep white title/subtitle readable over a bottom scrim.
    private static let pairs: [(UIColor, UIColor)] = [
        (rgb(0.20, 0.48, 0.78), rgb(0.10, 0.24, 0.52)),
        (rgb(0.18, 0.62, 0.58), rgb(0.08, 0.36, 0.42)),
        (rgb(0.86, 0.42, 0.28), rgb(0.58, 0.18, 0.22)),
        (rgb(0.72, 0.32, 0.55), rgb(0.38, 0.14, 0.42)),
        (rgb(0.92, 0.58, 0.22), rgb(0.62, 0.28, 0.12)),
        (rgb(0.28, 0.55, 0.32), rgb(0.12, 0.32, 0.24)),
        (rgb(0.22, 0.38, 0.68), rgb(0.35, 0.20, 0.55)),
        (rgb(0.55, 0.28, 0.22), rgb(0.28, 0.14, 0.18)),
        (rgb(0.15, 0.55, 0.72), rgb(0.08, 0.28, 0.48)),
        (rgb(0.48, 0.42, 0.78), rgb(0.22, 0.18, 0.48)),
        (rgb(0.78, 0.35, 0.38), rgb(0.42, 0.16, 0.32)),
        (rgb(0.32, 0.58, 0.48), rgb(0.16, 0.32, 0.42))
    ]

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func stableIndex(for id: UUID) -> Int {
        withUnsafeBytes(of: id.uuid) { buffer in
            var hash = 0
            for byte in buffer {
                hash = hash &* 31 &+ Int(byte)
            }
            return abs(hash)
        }
    }
}
