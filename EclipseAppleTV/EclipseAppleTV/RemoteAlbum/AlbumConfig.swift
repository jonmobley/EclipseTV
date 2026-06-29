//
//  AlbumConfig.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// AlbumConfig.swift
import Foundation

/// Central configuration for the remote-album feature.
///
/// The album host is hardcoded here so users never type or paste a full URL: they
/// enter a short per-account code (on the iPhone or directly on the TV) and the TV
/// composes the manifest URL from `manifestBase` + the code. The manifest returns *all*
/// of that account's albums. Changing hosts is a one-line edit here.
enum AlbumConfig {

    /// Base manifest endpoint. The account code is passed as a `code` query parameter,
    /// e.g. `https://aircamtv.com/api/public/manifest?code=123456`.
    static let manifestBase = "https://aircamtv.com/api/public/manifest"

    /// Number of digits in an account code.
    static let codeLength = 6

    // MARK: - Realtime (Supabase)

    /// Supabase project URL used for the Realtime WebSocket that pushes "album changed"
    /// nudges to the TV.
    static let supabaseURL = URL(string: "https://touuktwdhqabdnbhghyr.supabase.co")!

    /// Supabase anon (public) API key. This is safe to ship in the client; it only grants
    /// the access the project's RLS / Realtime authorization policies allow. The change
    /// broadcasts are sent server-side with the service-role key, so the TV only needs to
    /// subscribe (read) on the public `album-updates:<code>` channel.
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRvdXVrdHdkaHFhYmRuYmhnaHlyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MDAyMDksImV4cCI6MjA5ODA3NjIwOX0.vnrNkqR5GdYDYI4wamccRUeFWZxwZO80L7kBC5eFZj0"

    /// Whether Realtime is configured (placeholders above have been replaced). When false,
    /// the app skips opening the WebSocket and relies on launch/foreground/manual sync.
    static var isRealtimeConfigured: Bool {
        !supabaseURL.absoluteString.contains("YOUR-PROJECT-REF")
            && !supabaseAnonKey.contains("YOUR-SUPABASE-ANON-KEY")
    }

    /// Broadcast topic the TV subscribes to for a given account code. The backend must
    /// emit a broadcast on this exact topic (event `changed`) whenever the account's
    /// album items change.
    static func realtimeTopic(forCode code: String) -> String {
        "album-updates:\(normalize(code))"
    }

    /// Broadcast event name carrying the "re-sync now" nudge.
    static let realtimeChangeEvent = "changed"

    /// Normalizes raw user input into a candidate code (keeps digits only, so spaces or
    /// stray separators a user might type are dropped).
    static func normalize(_ raw: String) -> String {
        raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Whether `code` is a syntactically valid account code (exactly `codeLength` digits).
    /// Assumes input has already been normalized via `normalize(_:)`.
    static func isValidCode(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy(\.isNumber)
    }

    /// Composes the manifest URL for a validated account `code`, or `nil` if the code is
    /// malformed. Uses `URLComponents` so the code is correctly percent-encoded.
    static func manifestURL(forCode code: String) -> URL? {
        let normalized = normalize(code)
        guard isValidCode(normalized),
              var components = URLComponents(string: manifestBase) else { return nil }
        components.queryItems = [URLQueryItem(name: "code", value: normalized)]
        return components.url
    }
}
