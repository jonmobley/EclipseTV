//
//  ShowSlideshowToken.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Reserved surface ids for slideshow tiles in `LocalAlbum.surfaceIds`.
///
/// Prefixed so they never collide with media, website, or PDF membership ids.
enum ShowSlideshowToken {
    static let prefix = "__eclipse.slideshow."

    /// Surface id for the slideshow with `id`.
    static func token(for id: UUID) -> String {
        prefix + id.uuidString
    }

    /// Whether `id` is a slideshow surface token.
    static func isSlideshow(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// Slideshow UUID encoded in `token`, if it is a valid slideshow surface id.
    static func slideshowId(from token: String) -> UUID? {
        guard isSlideshow(token) else { return nil }
        return UUID(uuidString: String(token.dropFirst(prefix.count)))
    }
}
