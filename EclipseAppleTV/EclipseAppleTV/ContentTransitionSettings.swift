//
//  ContentTransitionSettings.swift
//  EclipseAppleTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Cut vs Crossfade for fullscreen content switches. Synced from the iPhone companion.
enum ContentTransitionSettings {
    private static let key = "EclipseTV.contentTransition"

    enum Style: String {
        case cut = "Cut"
        case crossfade = "Crossfade"
    }

    /// Defaults to Cut when unset or unknown.
    static var style: Style {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = Style(rawValue: raw) else {
                return .cut
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    /// Applies a wire value from the companion (`"Cut"` / `"Crossfade"`).
    static func apply(wireValue: String?) {
        guard let wireValue, let style = Style(rawValue: wireValue) else { return }
        self.style = style
    }
}
