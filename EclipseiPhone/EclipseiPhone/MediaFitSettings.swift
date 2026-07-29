//
//  MediaFitSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// How a still is framed inside the external-display panel.
enum MediaFitMode: String, CaseIterable {
    /// Whole image visible, letterboxed to the panel. Default for library stills.
    case fit = "Fit"
    /// Image fills the panel edge to edge; overflowing sides are cropped.
    case fill = "Fill"

    var contentMode: UIView.ContentMode {
        self == .fill ? .scaleAspectFill : .scaleAspectFit
    }

    var iconName: String {
        self == .fill
            ? "rectangle.arrowtriangle.2.outward"
            : "rectangle.arrowtriangle.2.inward"
    }
}

/// Per-item Fit / Fill choice for stills sent to the external display.
///
/// Stored as a light `[itemId: rawValue]` map in `UserDefaults` alongside the other
/// `ExternalOutputSettings` preferences. Items without an entry use `.fit`, so the
/// map only ever holds the stills the user explicitly switched to Fill.
enum MediaFitSettings {
    private static let key = "EclipseTV.media.fitModes"

    /// Fit / Fill for `id`, defaulting to `.fit`.
    static func mode(forId id: String) -> MediaFitMode {
        guard let raw = storedModes()[id], let mode = MediaFitMode(rawValue: raw) else {
            return .fit
        }
        return mode
    }

    /// Whether `id` should fill (and crop to) the external panel.
    static func isFill(forId id: String) -> Bool {
        mode(forId: id) == .fill
    }

    static func setMode(_ mode: MediaFitMode, forId id: String) {
        var modes = storedModes()
        if mode == .fit {
            modes.removeValue(forKey: id)
        } else {
            modes[id] = mode.rawValue
        }
        UserDefaults.standard.set(modes, forKey: key)
    }

    /// Drops a deleted item's choice so the map doesn't accumulate dead ids.
    static func clear(forId id: String) {
        var modes = storedModes()
        guard modes.removeValue(forKey: id) != nil else { return }
        UserDefaults.standard.set(modes, forKey: key)
    }

    private static func storedModes() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
