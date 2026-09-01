//
//  ShowCountdownToken.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Reserved surface ids for countdown tiles in `LocalAlbum.surfaceIds`.
///
/// Prefixed so they never collide with media, website, or PDF membership ids.
enum ShowCountdownToken {
    static let prefix = "__eclipse.countdown."
    /// Retired singleton tool token; migrated to a `ShowCountdown` on load.
    static let legacyTool = "__eclipse.tool.countdown"

    /// Surface id for the countdown with `id`.
    static func token(for id: UUID) -> String {
        prefix + id.uuidString
    }

    /// Whether `id` is a countdown surface token.
    static func isCountdown(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// Countdown UUID encoded in `token`, if it is a valid countdown surface id.
    static func countdownId(from token: String) -> UUID? {
        guard isCountdown(token) else { return nil }
        return UUID(uuidString: String(token.dropFirst(prefix.count)))
    }
}
