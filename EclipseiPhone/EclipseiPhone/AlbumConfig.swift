// AlbumConfig.swift
import Foundation

/// Configuration for the remote-album feature on the iPhone companion.
///
/// IMPORTANT: This mirrors `AlbumConfig` in the Apple TV target
/// (`EclipseAppleTV/EclipseAppleTV/RemoteAlbum/AlbumConfig.swift`). The two targets
/// don't share source, so the host and code rules are intentionally duplicated and
/// MUST stay in sync (same as `EclipseShareProtocol`).
///
/// The iPhone fetches the same account manifest the TV does, so it can browse the
/// account's albums directly over HTTPS without involving the Apple TV.
enum AlbumConfig {

    /// Base manifest endpoint. The account code is passed as a `code` query parameter,
    /// e.g. `https://aircamtv.com/api/public/manifest?code=123456`.
    static let manifestBase = "https://aircamtv.com/api/public/manifest"

    /// Number of digits in an account code.
    static let codeLength = 6

    /// Normalizes raw user input into a candidate code (keeps digits only).
    static func normalize(_ raw: String) -> String {
        raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Whether `code` is a syntactically valid account code (exactly `codeLength` digits).
    static func isValidCode(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy(\.isNumber)
    }

    /// Composes the manifest URL for a validated account `code`, or `nil` if malformed.
    static func manifestURL(forCode code: String) -> URL? {
        let normalized = normalize(code)
        guard isValidCode(normalized),
              var components = URLComponents(string: manifestBase) else { return nil }
        components.queryItems = [URLQueryItem(name: "code", value: normalized)]
        return components.url
    }
}
