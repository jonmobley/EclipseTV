//
//  Haptics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Centralized haptic feedback so call sites stay consistent.
enum Haptics {

    /// Light tap for selection / go-live affirmations.
    static func impactLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap for primary actions (shutter, confirm).
    static func impactMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Selection tick for toggling options.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Success notification (lock, copy, arrange done).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification (soft failures).
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error notification paired with failure alerts.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
