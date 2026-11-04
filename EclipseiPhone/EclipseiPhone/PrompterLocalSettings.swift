//
//  PrompterLocalSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Per-device Prompter preferences. Never synced: an iPad on a stand and a phone in
/// hand want different text sizes, and the Mac keeps its own.
@MainActor
struct PrompterLocalSettings {

    static let speedKey = "EclipseTV.prompter.scrollSpeed"
    static let fontSizeKey = "EclipseTV.prompter.fontSize"

    private let defaults: UserDefaults
    private let isPad: Bool

    init(defaults: UserDefaults = .standard, isPad: Bool? = nil) {
        self.defaults = defaults
        self.isPad = isPad ?? (UIDevice.current.userInterfaceIdiom == .pad)
    }

    var scrollSpeed: Double {
        get {
            let stored = defaults.object(forKey: Self.speedKey) as? Double
            return PrompterStageMetrics.clampedSpeed(stored ?? PrompterScrollEngine.defaultSpeed)
        }
        nonmutating set {
            defaults.set(PrompterStageMetrics.clampedSpeed(newValue), forKey: Self.speedKey)
        }
    }

    var fontSize: CGFloat {
        get {
            let stored = defaults.object(forKey: Self.fontSizeKey) as? Double
            let fallback = PrompterStageMetrics.defaultOperatorFontSize(isPad: isPad)
            return PrompterStageMetrics.clampedOperatorFontSize(stored.map { CGFloat($0) } ?? fallback)
        }
        nonmutating set {
            defaults.set(Double(PrompterStageMetrics.clampedOperatorFontSize(newValue)), forKey: Self.fontSizeKey)
        }
    }
}
