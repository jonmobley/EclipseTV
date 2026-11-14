//
//  PrompterLocalSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Per-device Prompter preferences. Never synced: the Mac keeps its own, and the
/// script is what travels between devices.
@MainActor
struct PrompterLocalSettings {

    static let speedKey = "EclipseTV.prompter.scrollSpeed"
    static let fontSizeKey = "EclipseTV.prompter.fontSize"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    /// Text size in canvas points (see `PrompterStageMetrics`).
    var fontSize: CGFloat {
        get {
            let stored = defaults.object(forKey: Self.fontSizeKey) as? Double
            let value = stored.map { CGFloat($0) } ?? PrompterStageMetrics.defaultCanvasFontSize
            return PrompterStageMetrics.clampedCanvasFontSize(value)
        }
        nonmutating set {
            defaults.set(Double(PrompterStageMetrics.clampedCanvasFontSize(newValue)), forKey: Self.fontSizeKey)
        }
    }
}
