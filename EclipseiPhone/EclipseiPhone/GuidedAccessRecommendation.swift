//
//  GuidedAccessRecommendation.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Copy and live status for the Settings Guided Access recommendation.
enum GuidedAccessRecommendation {

    static let settingsHeader = "Recommendations"
    static let rowTitle = "Guided Access"
    static let statusOn = "On"
    static let statusOff = "Off"

    static let settingsFooter =
        "Turn on Guided Access in Settings → Accessibility before you present. "
        + "It locks Eclipse on screen so an accidental Home swipe doesn’t AirPlay "
        + "your iPhone to the audience."

    static let whyTitle = "While presenting"
    static let whyBody =
        "If you leave Eclipse during AirPlay, the TV can switch to a mirror of "
        + "this iPhone — Home Screen, notifications, messages, and other apps. "
        + "Guided Access keeps Eclipse open until you end the session with "
        + "your passcode."

    static let howTitle = "Turn it on"
    static let howSteps: [String] = [
        "Open the Settings app, then Accessibility → Guided Access, and turn it on. Set a passcode.",
        "Return to Eclipse.",
        "Triple-click the Side button (or the Home button) and tap Start.",
        "Triple-click again and enter the passcode when you’re done presenting.",
    ]

    /// "On" when a Guided Access session is active on this device.
    static var statusText: String {
        UIAccessibility.isGuidedAccessEnabled ? statusOn : statusOff
    }
}
