//
//  ImageFramingSettings.swift
//  EclipseAppleTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Per-item custom crop position for stills, mirrored from the iPhone companion.
///
/// Keyed by file name (the wire item id) as `[name: [x, y, width, height]]` in
/// UserDefaults. Items without an entry use Fit / Fill alone.
enum ImageFramingSettings {
    private static let key = "EclipseTV.ImageFraming"

    /// Saved framing for a still by file name, or nil when Fit / Fill alone apply.
    static func framing(forFileName name: String) -> MediaFramingDTO? {
        guard let values = stored()[name],
              values.count == 4,
              values[2] > 0, values[3] > 0 else { return nil }
        return MediaFramingDTO(
            x: values[0], y: values[1], width: values[2], height: values[3]
        )
    }

    /// Framing for a still by its on-disk path.
    static func framing(forPath path: String) -> MediaFramingDTO? {
        framing(forFileName: (path as NSString).lastPathComponent)
    }

    static func set(_ framing: MediaFramingDTO, forFileName name: String) {
        var map = stored()
        map[name] = [framing.x, framing.y, framing.width, framing.height]
        UserDefaults.standard.set(map, forKey: key)
    }

    static func clear(forFileName name: String) {
        var map = stored()
        guard map.removeValue(forKey: name) != nil else { return }
        UserDefaults.standard.set(map, forKey: key)
    }

    private static func stored() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}
