//
//  PreviewCloseButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIButton {

    /// Dark glass disk with a white glyph, so overlay chrome stays legible over any
    /// photo or video frame.
    ///
    /// The faint white stroke is what keeps the disk readable against letterboxing:
    /// a dark blur over black is invisible without an edge. The shadow does the same
    /// job at the other extreme, over a blown-out sky.
    ///
    /// - Parameters:
    ///   - systemName: SF Symbol for the glyph.
    ///   - accessibilityLabel: Spoken label for the button.
    func applyPreviewChromeAppearance(systemName: String, accessibilityLabel: String) {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        config.image = UIImage(systemName: systemName, withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 9, leading: 9, bottom: 9, trailing: 9
        )

        var background = UIBackgroundConfiguration.clear()
        if UIAccessibility.isReduceTransparencyEnabled {
            background.backgroundColor = UIColor(white: 0.14, alpha: 1)
        } else {
            background.visualEffect = UIBlurEffect(style: .systemThinMaterialDark)
        }
        background.strokeColor = UIColor.white.withAlphaComponent(0.28)
        background.strokeWidth = 0.5
        config.background = background

        configuration = config
        self.accessibilityLabel = accessibilityLabel
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = .zero
    }

    /// Close chrome for a fullscreen Preview.
    ///
    /// Do not use `xmark.circle.fill` with `.alwaysOriginal`: that symbol’s default
    /// multicolor is a red badge, which reads as delete or an error.
    func applyPreviewCloseAppearance() {
        applyPreviewChromeAppearance(systemName: "xmark", accessibilityLabel: "Close")
    }

    /// Share chrome for a fullscreen Preview (opens the system share sheet).
    func applyPreviewShareAppearance() {
        applyPreviewChromeAppearance(
            systemName: "square.and.arrow.up", accessibilityLabel: "Share"
        )
        // The glyph's arrow sits above its tray, so centering the bounding box reads
        // as low in the disk; nudge it back up.
        configuration?.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 9, bottom: 11, trailing: 9
        )
    }
}
