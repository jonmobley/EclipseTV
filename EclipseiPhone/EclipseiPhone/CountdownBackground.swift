//
//  CountdownBackground.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Foundation

/// What renders behind a countdown clock on output.
///
/// Always a reference, never a copy. Show media, the Screensaver, and the Background
/// still already live on disk and sync through their own records, so a countdown only
/// names one of them. Nothing here owns a file, which is why adding a background costs
/// one string field instead of a per-countdown asset store.
enum CountdownBackground: Equatable, Hashable, Codable {
    /// Solid black behind the clock — the original look, offered as "None".
    ///
    /// Named `black` rather than `none` so `someCountdown?.background == .black`
    /// cannot silently resolve to `Optional.none` and compare against nil instead.
    case black
    /// A still or video already in this Show, by library media id.
    case libraryItem(id: String)
    /// Whatever the Screensaver tile holds — bundled loop, custom video, or still.
    case screensaver
    /// The Background still from the Show tools.
    case background

    /// Scrim alpha laid over any background so the digits stay legible.
    ///
    /// Deliberately not user-adjustable: the clock is stage-critical timing
    /// information, and white text on an undimmed photo is unreadable from the room.
    static let scrimAlpha: CGFloat = 0.45

    /// Round-trip token for JSON and CloudKit.
    var token: String {
        switch self {
        case .black: return ""
        case .screensaver: return "screensaver"
        case .background: return "background"
        case .libraryItem(let id): return Self.mediaPrefix + id
        }
    }

    /// Parses `token`, falling back to `.black` for anything unrecognized.
    ///
    /// A newer build's token must degrade to black rather than fail the whole decode.
    init(token: String?) {
        guard let token, !token.isEmpty else {
            self = .black
            return
        }
        switch token {
        case "screensaver":
            self = .screensaver
        case "background":
            self = .background
        default:
            let id = token.hasPrefix(Self.mediaPrefix)
                ? String(token.dropFirst(Self.mediaPrefix.count))
                : ""
            self = id.isEmpty ? .black : .libraryItem(id: id)
        }
    }

    /// Library media id this background points at, if any.
    var libraryItemId: String? {
        guard case .libraryItem(let id) = self else { return nil }
        return id
    }

    private static let mediaPrefix = "media:"

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        self.init(token: token)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}

// MARK: - Resolved Media

/// Renderable media a countdown background resolves to.
enum CountdownBackgroundMedia: Equatable {
    /// Aspect-fill still at a local file URL.
    case still(URL)
    /// Muted aspect-fill loop. `crossfade` blends the loop point.
    case loop(url: URL, crossfade: Bool)
}

@MainActor
extension CountdownBackground {

    /// Saved background for the countdown with `id`.
    static func resolved(for id: UUID) -> CountdownBackground {
        CountdownStore.shared.countdown(id: id)?.background ?? .black
    }

    /// Renderable media, or nil when nothing is set or the referenced file is gone.
    ///
    /// A missing file resolves to nil so output falls back to plain black instead of
    /// failing — the same treatment purged media gets everywhere else.
    var media: CountdownBackgroundMedia? {
        switch self {
        case .black:
            return nil
        case .screensaver:
            return Self.media(from: ScreensaverStore.presentationSource)
        case .background:
            return Self.media(from: LogoStore.shared.presentationSource)
        case .libraryItem(let id):
            return Self.libraryMedia(id: id)
        }
    }

    private static func media(
        from source: PresentationSource?
    ) -> CountdownBackgroundMedia? {
        switch source?.content {
        case .image(let url, _, _):
            return .still(url)
        case .screensaver(let url, let crossfade):
            return .loop(url: url, crossfade: crossfade)
        case .video(let url, _, _):
            return .loop(url: url, crossfade: false)
        default:
            return nil
        }
    }

    private static func libraryMedia(id: String) -> CountdownBackgroundMedia? {
        guard let url = LocalMediaStore.shared.localURL(forId: id) else { return nil }
        let isVideo = TVLibraryStore.shared.items.first { $0.id == id }?.isVideo
            ?? Self.hasVideoExtension(url)
        // Background clips loop gaplessly; blending the seam double-exposes it.
        return isVideo ? .loop(url: url, crossfade: false) : .still(url)
    }

    private static func hasVideoExtension(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }
}
