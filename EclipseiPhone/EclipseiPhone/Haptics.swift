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

    /// Heavy tap for capture-style moments (record start / stop).
    static func impactHeavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Soft tap for drawer / sheet snaps that should stay unobtrusive.
    static func impactSoft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Rigid tap for entering a mode (select, arrange).
    static func impactRigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// Impact tap for a style chosen at runtime (e.g. by gesture velocity).
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
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
