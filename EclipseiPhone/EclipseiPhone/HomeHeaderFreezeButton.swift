//
//  HomeHeaderFreezeButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Look of the header Freeze control: a snowflake (same glyph as the Mac) that
/// fills blue when the audience screen is held still, like the Blackout moon.
///
/// Thread safety: main thread only (UIKit).
enum HomeHeaderFreezeStyle {

    /// Same glyph as the Mac's Freeze control.
    static let symbolName = "snowflake"

    /// Names the button for VoiceOver (draw it with `apply`).
    static func label(_ button: UIButton) {
        button.accessibilityLabel = "Freeze"
        button.accessibilityHint = "Holds the audience screen on the current picture "
            + "while you keep working. Tap again to show what is live now"
    }

    /// Draws the button on or off.
    static func apply(to button: UIButton, frozen: Bool) {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        if frozen {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .accent
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            button.configuration = config
        } else {
            button.configuration = HomeHeaderBar.barIconConfig(
                systemName: symbolName,
                symbolConfig: symbolConfig
            )
        }
        button.accessibilityValue = frozen ? "On" : "Off"
    }
}
