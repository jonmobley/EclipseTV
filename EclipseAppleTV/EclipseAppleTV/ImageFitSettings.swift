//
//  ImageFitSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// How a still is framed on the TV screen.
enum ImageFitMode: String {
    /// Whole image visible, letterboxed to the screen. Default, matching the companion.
    case fit = "Fit"
    /// Image fills the screen; overflowing edges are cropped.
    case fill = "Fill"

    var contentMode: UIView.ContentMode {
        self == .fill ? .scaleAspectFill : .scaleAspectFit
    }
}

/// Per-item Fit / Fill framing for stills, mirrored from the iPhone companion.
///
/// The companion owns the choice (it needs it for its own AirPlay output), and pushes it
/// down with every `playRequest` plus a `setImageFit` when it changes mid-show. Storing it
/// here keeps the framing correct when the TV shows an item on its own — remote
/// navigation, grid taps, or the first item after a relaunch.
///
/// Keyed by file name (the wire item id) as a small `[name: rawValue]` map in
/// `UserDefaults`, alongside `EclipseTV.VideoSettings`. Anything without an entry is Fit.
enum ImageFitSettings {
    private static let key = "EclipseTV.ImageFit"

    /// Framing for a still by its file name, defaulting to `.fit`.
    static func mode(forFileName name: String) -> ImageFitMode {
        guard let raw = storedModes()[name], let mode = ImageFitMode(rawValue: raw) else {
            return .fit
        }
        return mode
    }

    /// Framing for a still by its on-disk path.
    static func mode(forPath path: String) -> ImageFitMode {
        mode(forFileName: (path as NSString).lastPathComponent)
    }

    static func setFill(_ isFill: Bool, forFileName name: String) {
        var modes = storedModes()
        if isFill {
            modes[name] = ImageFitMode.fill.rawValue
        } else {
            modes.removeValue(forKey: name)
        }
        UserDefaults.standard.set(modes, forKey: key)
    }

    private static func storedModes() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
