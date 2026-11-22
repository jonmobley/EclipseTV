//
//  ShippedVideo.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Videos that ship inside the app (the Eclipse loop).
///
/// They repeat by default and blend their loop point, matching the iPhone's
/// bundled Screensaver. Videos sent from a phone live in the app's caches and
/// keep their own settings and a hard, gapless loop.
///
/// Thread Safety: Pure helpers - safe from any thread.
enum ShippedVideo {

    /// Whether `path` is a video that ships with the app.
    ///
    /// Bundled files sit inside the `.app` folder; the old `Videos/Loop`
    /// folder name is still honored for any build that keeps it.
    /// - Parameter path: A video file path
    /// - Returns: `true` for videos shipped inside the app
    static func isShipped(path: String) -> Bool {
        path.contains(".app/") || path.contains("/Loop/")
    }

    /// Every video file bundled with the app.
    static var bundledURLs: [URL] {
        MediaItem.videoExtensions.sorted().flatMap {
            Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? []
        }
    }
}
