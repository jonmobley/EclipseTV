//
//  DefaultsKeys.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Naming home for `UserDefaults` keys.
///
/// The convention is `EclipseTV.<feature>.<name>` — the prefix predates the split
/// into two apps and is shared with the Apple TV target. Stores keep their own
/// `private static let …Key` constants next to the code that reads them; new keys
/// are minted with `make(_:)` so the prefix stays uniform.
///
/// Keys that shipped under another prefix are listed here as frozen legacy values.
/// They are live in users' defaults and must never be renamed: doing so silently
/// resets the preference (or, for the album manifest, drops downloaded state).
enum DefaultsKeys {

    /// Prefix for every new key.
    static let prefix = "EclipseTV."

    /// Builds a conventional key, e.g. `make("camera.mirror")` → `EclipseTV.camera.mirror`.
    static func make(_ suffix: String) -> String {
        prefix + suffix
    }

    // MARK: - Frozen legacy keys (do not rename)

    /// Ambient music volume. `Eclipse.` prefix predates the convention.
    static let audioPlayerVolume = "Eclipse.audio.playerVolume"
    /// Ambient music "plays next" flag.
    static let audioPlaysNext = "Eclipse.audio.playsNext"
    /// Pre-account Live Poll host PIN, read once for migration.
    static let legacyLivePollHostPIN = "Eclipse.questpoll.hostPin"
    /// Whether the PIN → account migration prompt has been shown.
    static let livePollDidPromptPINMigration = "Eclipse.livepoll.didPromptPINMigration"
    /// Shared-album join code. `EclipseiPhone.` prefix predates the convention.
    static let albumBrowserCode = "EclipseiPhone.album.code"
    /// Cached shared-album manifest.
    static let albumBrowserManifest = "EclipseiPhone.album.manifest"

    /// Poster frame chosen for a video before it was sent to EclipseTV, keyed by the
    /// transfer file name. Bare prefix predates the convention.
    static func customThumbnail(fileName: String) -> String {
        "customThumbnail_\(fileName)"
    }
}
