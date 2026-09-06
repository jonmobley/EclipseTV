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
    static let statusSessionActive = "Session active"
    static let statusNoSession = "Not in a session"

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

    /// Reflects whether a Guided Access session is running right now. iOS gives
    /// apps no way to read the Settings → Accessibility toggle itself, so the
    /// wording deliberately avoids "On"/"Off".
    static var statusText: String {
        UIAccessibility.isGuidedAccessEnabled ? statusSessionActive : statusNoSession
    }
}
