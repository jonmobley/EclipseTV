//
//  SessionCookieParser.swift
//  EclipseRemoteProtocol
//
//  Description: Extracts the Eclipse remote session token from Set-Cookie.
//  Thread Safety: Pure helpers — safe from any isolation domain.
//

import Foundation

// MARK: - SessionCookieParser

/// Parses `Set-Cookie` headers produced by `POST /session` and `POST /pair`.
///
/// Thread Safety: Stateless; safe to call from any thread.
public enum SessionCookieParser {

    /// Cookie name used by the Mac remote server.
    public static let cookieName = "eclipse_remote"

    /// Returns the session token from a `Set-Cookie` header value, if present.
    /// - Parameter setCookieHeader: Raw `Set-Cookie` header body.
    /// - Returns: Token string, or nil when the header is not a session cookie.
    public static func token(fromSetCookieHeader setCookieHeader: String) -> String? {
        for part in setCookieHeader.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2, pieces[0] == cookieName else { continue }
            return pieces[1].isEmpty ? nil : pieces[1]
        }
        return nil
    }

    /// Scans URLResponse header fields for the session cookie token.
    /// - Parameter response: HTTP URL response from `/session` or `/pair`.
    /// - Returns: Token when found.
    public static func token(from response: URLResponse) -> String? {
        guard let http = response as? HTTPURLResponse else { return nil }
        // URLSession may coalesce duplicate Set-Cookie; check both forms.
        if let single = http.value(forHTTPHeaderField: "Set-Cookie"),
           let token = token(fromSetCookieHeader: single) {
            return token
        }
        for (key, value) in http.allHeaderFields {
            guard String(describing: key).lowercased() == "set-cookie",
                  let token = token(fromSetCookieHeader: String(describing: value)) else {
                continue
            }
            return token
        }
        return nil
    }

    /// Fallback when URLSession strips `Set-Cookie` after storing HttpOnly cookies.
    /// - Parameters:
    ///   - storage: The session's cookie storage (ephemeral jar is fine).
    ///   - url: Request URL / origin used for the pair or session call.
    /// - Returns: Token when the jar holds `eclipse_remote` for that URL.
    public static func token(from storage: HTTPCookieStorage?, url: URL) -> String? {
        guard let cookies = storage?.cookies(for: url) else { return nil }
        return cookies.first(where: { $0.name == cookieName })?.value
    }
}
