//
//  StackedHeroMetrics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Stacked (portrait / iPad) live-preview height.
///
/// Compact width keeps a 280pt cap so a 9:16 Vertical hero does not fill the
/// phone. Regular width (full-screen iPad) scales the preview with the pane
/// instead of staying phone-sized.
enum StackedHeroMetrics {

    /// Compact-width cap (any shape whose full-width card would be taller).
    static let phoneMaxHeight: CGFloat = 280
    /// Fraction of the pane’s safe height used by the preview on regular width.
    static let regularWidthHeightFraction: CGFloat = 0.45
    /// Shortest / tallest pane still treated as a phone turned sideways.
    static let phoneLandscapeMinPaneHeight: CGFloat = 280
    static let phoneLandscapeMaxPaneHeight: CGFloat = 520
    /// Hero card height budget on a phone-landscape pane, as a fraction of its height.
    ///
    /// A full-bleed 16:9 of the long edge is taller than the phone, so the card
    /// stays full width and this fraction leaves a row of Recent underneath.
    static let phoneLandscapeHeroHeightFraction: CGFloat = 0.40

    /// A wide, short pane: iPhone landscape, including Plus / Max.
    ///
    /// Requires a clearly wide ratio so a mid-rotation frame doesn't take this path.
    /// iPad landscape is taller than `phoneLandscapeMaxPaneHeight` and stays out.
    static func isPhoneLandscapePane(width: CGFloat, height: CGFloat) -> Bool {
        guard height >= phoneLandscapeMinPaneHeight,
              height < phoneLandscapeMaxPaneHeight
        else { return false }
        return width > height * 1.15
    }

    /// Size of the stacked preview card for a picture of `aspect` (width ÷ height).
    ///
    /// Full width when that is no taller than `maxHeight`; otherwise `maxHeight`
    /// tall, narrower, and centred. One rule for every shape: 16:9 fills the
    /// width, 9:16 and a tall LED wall are capped, a wide wall is a short banner.
    /// - Parameters:
    ///   - bleedWidth: The pane's width inside the header insets.
    ///   - maxHeight: The cap from `maxHeight(containerSize:…)`.
    ///   - aspect: Width ÷ height of the output picture.
    /// - Returns: The card size, and whether it spans the full width.
    static func stackedSize(
        bleedWidth: CGFloat,
        maxHeight: CGFloat,
        aspect: CGFloat
    ) -> (size: CGSize, isFullBleed: Bool) {
        guard aspect > 0, bleedWidth > 0 else {
            return (CGSize(width: max(0, bleedWidth), height: maxHeight), true)
        }
        let bleedHeight = bleedWidth / aspect
        if bleedHeight <= maxHeight + 1 {
            return (CGSize(width: bleedWidth, height: bleedHeight), true)
        }
        return (CGSize(width: (maxHeight * aspect).rounded(.down), height: maxHeight), false)
    }

    /// Max stacked-hero height for the current Display Mode aspect.
    static func maxHeight(
        containerSize: CGSize,
        horizontalSizeClass: UIUserInterfaceSizeClass,
        headerInset: CGFloat,
        safeAreaInsets: UIEdgeInsets,
        aspectWidthOverHeight: CGFloat
    ) -> CGFloat {
        guard horizontalSizeClass == .regular,
              containerSize.width > 0,
              containerSize.height > 0,
              aspectWidthOverHeight > 0
        else { return phoneMaxHeight }

        let maxWidth = max(0, containerSize.width - headerInset * 2)
        let fromWidth = maxWidth / aspectWidthOverHeight
        let availableHeight = max(
            0,
            containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
        let fromPane = availableHeight * regularWidthHeightFraction
        let scaled = min(fromWidth, fromPane).rounded(.down)
        return max(phoneMaxHeight, scaled)
    }
}
