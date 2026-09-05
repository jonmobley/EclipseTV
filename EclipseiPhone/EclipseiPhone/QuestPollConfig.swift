//
//  QuestPollConfig.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Hosted QuestPoll origin and projector URL.
///
/// `/present` takes `aspect=16x9` or `aspect=9x16` from Display Mode. Companion
/// hero and AirPlay fill the host 1:1; QuestPoll’s CSS stage scaler does the
/// only shrink/fit.
enum QuestPollConfig {
    static let origin = URL(string: "https://questpoll.live")!

    /// Host console for editing decks (Safari deep link).
    static let hostURL = origin.appendingPathComponent("host")

    /// Bare `/present` path. Query items (code, pollId, aspect) are added per URL.
    private static let presentPath = origin.appendingPathComponent("present")

    /// Display Mode for `/present`: Vertical is 9:16, Landscape is 16:9.
    static var presentAspectQueryItem: URLQueryItem {
        URLQueryItem(
            name: "aspect",
            value: ExternalOutputSettings.isVerticalMode ? "9x16" : "16x9"
        )
    }

    /// Audience / AirPlay page (QR + live question), unbound.
    static var presentURL: URL {
        projectorURL(queryItems: [])
    }

    /// Stable id for the in-hero projector preview (not a user bookmark).
    static let previewPageId = UUID(
        uuidString: "E0E0E0E0-0000-4000-8000-00000000C0DE"
    )!

    /// Audience join page bound to a room code (`/?code=`).
    static func joinURL(code: String) -> URL {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(
                url: origin, resolvingAgainstBaseURL: false
              )
        else { return origin }
        components.queryItems = [URLQueryItem(name: "code", value: trimmed)]
        return components.url ?? origin
    }

    /// Projector URL bound to a join code when the web app honors `?code=`.
    static func presentURL(code: String) -> URL {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return presentURL }
        return projectorURL(queryItems: [
            URLQueryItem(name: "code", value: trimmed)
        ])
    }

    /// Deck-only Practice preview (no room): `/present?pollId=&preview=1`.
    static func presentPreviewURL(pollId: String) -> URL {
        let trimmed = pollId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return presentURL }
        return projectorURL(queryItems: [
            URLQueryItem(name: "pollId", value: trimmed),
            URLQueryItem(name: "preview", value: "1")
        ])
    }

    /// Stable warm-pool id for a Practice deck preview.
    static func previewPageId(pollId: String) -> UUID {
        var hasher = Hasher()
        hasher.combine("eclipse.questpoll.preview")
        hasher.combine(pollId)
        let h = UInt64(bitPattern: Int64(hasher.finalize()))
        let mixed = h &* 0x9E3779B97F4A7C15
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: h >> 56),
            UInt8(truncatingIfNeeded: h >> 48),
            UInt8(truncatingIfNeeded: h >> 40),
            UInt8(truncatingIfNeeded: h >> 32),
            UInt8(truncatingIfNeeded: h >> 24),
            UInt8(truncatingIfNeeded: h >> 16),
            0x40 | UInt8(truncatingIfNeeded: (h >> 8) & 0x0F),
            UInt8(truncatingIfNeeded: h),
            0x80 | UInt8(truncatingIfNeeded: (mixed >> 56) & 0x3F),
            UInt8(truncatingIfNeeded: mixed >> 48),
            UInt8(truncatingIfNeeded: mixed >> 40),
            UInt8(truncatingIfNeeded: mixed >> 32),
            UInt8(truncatingIfNeeded: mixed >> 24),
            UInt8(truncatingIfNeeded: mixed >> 16),
            UInt8(truncatingIfNeeded: mixed >> 8),
            UInt8(truncatingIfNeeded: mixed)
        ))
    }

    /// Synthetic page so the warm web pool can attach `/present` to the hero.
    static var previewPage: WebPage {
        WebPage(id: previewPageId, title: "Live Poll", url: presentURL)
    }

    /// Projector page for an active room (falls back to unbound `/present`).
    static func previewPage(code: String?) -> WebPage {
        guard let code, !code.isEmpty else { return previewPage }
        return WebPage(
            id: previewPageId,
            title: "Live Poll",
            url: presentURL(code: code)
        )
    }

    /// Practice page for a deck without creating a room.
    static func previewPage(pollId: String) -> WebPage {
        WebPage(
            id: previewPageId(pollId: pollId),
            title: "Live Poll Practice",
            url: presentPreviewURL(pollId: pollId)
        )
    }

    /// Whether `url` is the QuestPoll projector page (path may grow a slash).
    static func isPresentURL(_ url: URL) -> Bool {
        url.host?.lowercased() == origin.host
            && url.path.hasPrefix("/present")
    }

    /// `/present` plus `items`, always ending with Display Mode `aspect=`.
    private static func projectorURL(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: presentPath, resolvingAgainstBaseURL: false
        )
        var items = queryItems
        items.append(presentAspectQueryItem)
        components?.queryItems = items
        return components?.url ?? presentPath
    }
}
