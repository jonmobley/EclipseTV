//
//  ShowLivePollToken.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Reserved surface ids for Live Poll cards in `LocalAlbum.surfaceIds`.
///
/// Prefixed so they never collide with media, website, or PDF membership ids.
enum ShowLivePollToken {
    static let prefix = "__eclipse.livePoll."
    /// Retired singleton tool token; dropped on load (no pollId to recover).
    static let legacyTool = "__eclipse.tool.livePoll"

    /// Surface id for the Live Poll membership with `id`.
    static func token(for id: UUID) -> String {
        prefix + id.uuidString
    }

    /// Whether `id` is a Live Poll surface token.
    static func isLivePoll(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// Membership UUID encoded in `token`, if it is a valid Live Poll surface id.
    static func livePollId(from token: String) -> UUID? {
        guard isLivePoll(token) else { return nil }
        return UUID(uuidString: String(token.dropFirst(prefix.count)))
    }
}
