//
//  WebVideoLink.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A website URL that should play as edge-to-edge video instead of a desktop page.
///
/// Derived from the bookmark URL at use time — never persisted — so existing
/// `WebPage` / CloudKit records need no migration.
enum WebVideoLink: Equatable, Hashable {
    /// YouTube video id plus optional start offset in seconds.
    case youTube(id: String, startAt: TimeInterval)
    /// Vimeo numeric id, optional unlisted hash, and optional start offset.
    case vimeo(id: String, hash: String?, startAt: TimeInterval)
    /// Direct progressive or HLS media URL (`.mp4`, `.m4v`, `.mov`, `.m3u8`).
    case directFile(URL)

    /// Recognizes YouTube, Vimeo, and direct media URLs. Returns `nil` for ordinary pages.
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        let host = (url.host ?? "").lowercased()
        if Self.isYouTubeHost(host), let parsed = Self.parseYouTube(url) {
            self = parsed
            return
        }
        if Self.isVimeoHost(host), let parsed = Self.parseVimeo(url) {
            self = parsed
            return
        }
        if Self.isDirectMediaURL(url) {
            self = .directFile(url)
            return
        }
        return nil
    }

    /// Human-readable provider for UI chrome ("YouTube", "Vimeo", "Video").
    var providerName: String {
        switch self {
        case .youTube: return "YouTube"
        case .vimeo: return "Vimeo"
        case .directFile: return "Video"
        }
    }

    /// Official embed URL used inside the bare HTML shell (nil for direct files).
    var embedURL: URL? {
        switch self {
        case .youTube(let id, let startAt):
            var components = URLComponents(
                string: "https://www.youtube.com/embed/\(id)"
            )
            var items: [URLQueryItem] = [
                URLQueryItem(name: "autoplay", value: "1"),
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "rel", value: "0"),
                URLQueryItem(name: "modestbranding", value: "1"),
                URLQueryItem(name: "controls", value: "0"),
                URLQueryItem(name: "enablejsapi", value: "1")
            ]
            if startAt > 0 {
                items.append(URLQueryItem(name: "start", value: "\(Int(startAt))"))
            }
            components?.queryItems = items
            return components?.url
        case .vimeo(let id, let hash, let startAt):
            var components = URLComponents(
                string: "https://player.vimeo.com/video/\(id)"
            )
            var items: [URLQueryItem] = [
                URLQueryItem(name: "autoplay", value: "1"),
                URLQueryItem(name: "title", value: "0"),
                URLQueryItem(name: "byline", value: "0"),
                URLQueryItem(name: "portrait", value: "0"),
                URLQueryItem(name: "controls", value: "0"),
                URLQueryItem(name: "playsinline", value: "1")
            ]
            if let hash, !hash.isEmpty {
                items.append(URLQueryItem(name: "h", value: hash))
            }
            if startAt > 0 {
                items.append(URLQueryItem(name: "t", value: "\(Int(startAt))s"))
            }
            components?.queryItems = items
            return components?.url
        case .directFile:
            return nil
        }
    }

    /// Best-effort poster image URL (YouTube ytimg; Vimeo needs oEmbed).
    var posterURL: URL? {
        switch self {
        case .youTube(let id, _):
            return URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
        case .vimeo, .directFile:
            return nil
        }
    }

    /// Fallback YouTube poster when maxres is missing (404).
    var fallbackPosterURL: URL? {
        switch self {
        case .youTube(let id, _):
            return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        case .vimeo, .directFile:
            return nil
        }
    }

    /// Origin used as `loadHTMLString` baseURL so the IFrame API accepts postMessage.
    var shellBaseURL: URL? {
        switch self {
        case .youTube:
            return URL(string: "https://www.youtube.com")
        case .vimeo:
            return URL(string: "https://player.vimeo.com")
        case .directFile:
            return nil
        }
    }

    /// Start offset in seconds when known.
    var startAt: TimeInterval {
        switch self {
        case .youTube(_, let startAt), .vimeo(_, _, let startAt):
            return startAt
        case .directFile:
            return 0
        }
    }

    // MARK: - Host Checks

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com"
            || host == "www.youtube.com"
            || host == "m.youtube.com"
            || host == "music.youtube.com"
            || host == "youtu.be"
            || host == "www.youtu.be"
            || host == "youtube-nocookie.com"
            || host == "www.youtube-nocookie.com"
    }

    private static func isVimeoHost(_ host: String) -> Bool {
        host == "vimeo.com"
            || host == "www.vimeo.com"
            || host == "player.vimeo.com"
    }

    private static let directExtensions: Set<String> = [
        "mp4", "m4v", "mov", "m3u8"
    ]

    private static func isDirectMediaURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if directExtensions.contains(ext) { return true }
        // Query-stripped path (e.g. CDN URLs with ?token=).
        let pathExt = (url.path as NSString).pathExtension.lowercased()
        return directExtensions.contains(pathExt)
    }

    // MARK: - YouTube

    private static func parseYouTube(_ url: URL) -> WebVideoLink? {
        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map(String.init)
        let startAt = parseTimestamp(from: url)

        if host == "youtu.be" || host == "www.youtu.be" {
            guard let id = parts.first, isYouTubeVideoId(id) else { return nil }
            return .youTube(id: id, startAt: startAt)
        }

        guard let first = parts.first else { return nil }
        switch first {
        case "watch":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value
            guard let id, isYouTubeVideoId(id) else { return nil }
            return .youTube(id: id, startAt: startAt)
        case "shorts", "live", "embed", "v":
            guard parts.count >= 2, isYouTubeVideoId(parts[1]) else { return nil }
            return .youTube(id: parts[1], startAt: startAt)
        default:
            return nil
        }
    }

    private static func isYouTubeVideoId(_ id: String) -> Bool {
        // Standard ids are 11 chars [A-Za-z0-9_-]; allow a slightly wider range.
        guard id.count >= 6, id.count <= 20 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_" || scalar == "-"
        }
    }

    // MARK: - Vimeo

    private static func parseVimeo(_ url: URL) -> WebVideoLink? {
        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map(String.init)
        let startAt = parseTimestamp(from: url)

        if host == "player.vimeo.com" {
            // /video/ID or /video/ID?h=HASH
            guard parts.count >= 2, parts[0] == "video", isVimeoId(parts[1]) else {
                return nil
            }
            let hash = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "h" })?
                .value
            return .vimeo(id: parts[1], hash: hash, startAt: startAt)
        }

        guard !parts.isEmpty else { return nil }

        // /channels/name/ID
        if parts.count >= 3, parts[0] == "channels", isVimeoId(parts[2]) {
            return .vimeo(id: parts[2], hash: nil, startAt: startAt)
        }

        // /ID or /ID/HASH (unlisted)
        if isVimeoId(parts[0]) {
            let hash = parts.count >= 2 ? parts[1] : nil
            return .vimeo(id: parts[0], hash: hash, startAt: startAt)
        }

        return nil
    }

    private static func isVimeoId(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber)
    }

    // MARK: - Timestamps

    /// Parses `t=` / `start=` as seconds (`90`) or YouTube style (`1h2m3s`, `1m30s`).
    static func parseTimestamp(from url: URL) -> TimeInterval {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let raw = items?.first(where: { $0.name == "t" || $0.name == "start" })?.value
        guard let raw, !raw.isEmpty else { return 0 }
        return parseTimestampValue(raw)
    }

    /// Converts a timestamp string into seconds.
    static func parseTimestampValue(_ raw: String) -> TimeInterval {
        if let seconds = Double(raw), seconds >= 0 {
            return seconds
        }
        // 1h2m3s / 2m30s / 90s
        var total: TimeInterval = 0
        var number = ""
        for character in raw.lowercased() {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let value = Double(number) else {
                number = ""
                continue
            }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
            number = ""
        }
        if let trailing = Double(number), trailing > 0, total == 0 {
            return trailing
        }
        return max(0, total)
    }
}
