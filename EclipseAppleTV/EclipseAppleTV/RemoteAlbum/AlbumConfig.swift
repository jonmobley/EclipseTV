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
