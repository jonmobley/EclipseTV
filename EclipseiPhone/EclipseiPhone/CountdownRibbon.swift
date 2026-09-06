//
//  CountdownRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Placement and selection for the live countdown's duration strip.
enum CountdownRibbon {

    /// Duration chips while this Show's clock is the live overlay.
    ///
    /// Scoped to the open Show for the same reason the slideshow and Live Poll
    /// ribbons are: a clock live from another Show must not dock its presets
    /// under this Show's hero.
    static func shouldShow(
        isShowMode: Bool,
        isCountdownLive: Bool,
        belongsToOpenShow: Bool
    ) -> Bool {
        isShowMode && isCountdownLive && belongsToOpenShow
    }

    /// Chip index for `duration`, or the trailing Custom chip when it is not a preset.
    static func selectedIndex(duration: Int, presets: [Int]) -> Int {
        presets.firstIndex(of: duration) ?? presets.count
    }
}
