//
//  ConnectURLParser.swift
//  Eclipse
//
//  Description: Parses Eclipse remote connect URLs, including QR `#t=` tokens
//               and the `eclipse://mac-remote` app deep link.
//  Thread Safety: Pure helpers — safe from any isolation domain.
//

import Foundation

// MARK: - ConnectURLParser

/// Result of parsing an operator connect URL or typed host.
struct RemoteConnectInfo: Equatable, Sendable {
    /// Base origin such as `http://192.168.1.10:7878`.
    let baseURL: URL
    /// Bootstrap token from `#t=…` when present (QR path).
    let bootstrapToken: String?

    init(baseURL: URL, bootstrapToken: String?) {
        self.baseURL = baseURL
        self.bootstrapToken = bootstrapToken
    }
}

/// Parses phone-remote connect URLs produced by Eclipse Settings.
///
/// Accepts:
/// - App deep links: `eclipse://mac-remote?h=host&p=7878#t=TOKEN`
/// - Full HTTP URLs: `http://host:7878/#t=TOKEN`
/// - Bare hosts: `eclipse.local`, `192.168.1.10:7878`
///
/// Query `?t=` on HTTP URLs is ignored — only the fragment bootstrap secret is
/// read, matching the web client.
///
/// Thread Safety: Stateless; safe to call from any thread.
enum ConnectURLParser {

    /// Custom URL scheme registered by the Eclipse iPhone app.
    static let appScheme = "eclipse"
    /// Deep-link host for Mac remote pairing.
    static let appHost = "mac-remote"
    /// Default remote port when the operator omits one.
    static let defaultPort = 7878

    /// Builds the QR payload that opens the Eclipse iPhone app.
    /// - Parameters:
    ///   - host: mDNS or LAN host shown in Settings.
    ///   - port: Listener port.
    ///   - token: Bootstrap session token.
    /// - Returns: `eclipse://mac-remote?h=…&p=…#t=…`
    static func appDeepLink(host: String, port: Int, token: String) -> String {
        var components = URLComponents()
        components.scheme = appScheme
        components.host = appHost
        components.queryItems = [
            URLQueryItem(name: "h", value: host),
            URLQueryItem(name: "p", value: String(port))
        ]
        components.fragment = "t=\(token)"
        return components.string ?? "\(appScheme)://\(appHost)?h=\(host)&p=\(port)#t=\(token)"
    }

    /// Parses a typed, scanned, or deep-linked connect string.
    /// - Parameter raw: Deep link, URL, host, or `host:port`.
    /// - Returns: Normalized origin + optional bootstrap token, or nil.
    static func parse(_ raw: String) -> RemoteConnectInfo? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let fromApp = parseAppDeepLink(trimmed) {
            return fromApp
        }
        if let fromURL = parseAbsoluteHTTPURL(trimmed) {
            return fromURL
        }
        return parseHostPort(trimmed)
    }

    // MARK: - Private Helpers

    private static func parseAppDeepLink(_ raw: String) -> RemoteConnectInfo? {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == appScheme,
              url.host?.lowercased() == appHost else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let host = items.first(where: { $0.name == "h" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host, !host.isEmpty else { return nil }

        let portValue = items.first(where: { $0.name == "p" })?.value.flatMap(Int.init)
        let port = portValue ?? defaultPort
        guard port > 0, port < 65_536 else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        guard let base = components.url else { return nil }

        let token = bootstrapToken(fromFragment: url.fragment)
        return RemoteConnectInfo(baseURL: base, bootstrapToken: token)
    }

    private static func parseAbsoluteHTTPURL(_ raw: String) -> RemoteConnectInfo? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = url.port ?? defaultPort
        guard let base = components.url else { return nil }

        let token = bootstrapToken(fromFragment: url.fragment)
        return RemoteConnectInfo(baseURL: base, bootstrapToken: token)
    }

    private static func parseHostPort(_ raw: String) -> RemoteConnectInfo? {
        let withoutScheme = raw
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
        let hostPart = withoutScheme.split(separator: "/", maxSplits: 1).first
            .map(String.init) ?? withoutScheme

        let pieces = hostPart.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = pieces.first, !host.isEmpty else { return nil }
        let port = pieces.count == 2 ? Int(pieces[1]) : defaultPort
        guard let port, port > 0, port < 65_536 else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        guard let base = components.url else { return nil }
        return RemoteConnectInfo(baseURL: base, bootstrapToken: nil)
    }

    private static func bootstrapToken(fromFragment fragment: String?) -> String? {
        guard let fragment, fragment.hasPrefix("t=") else { return nil }
        let value = String(fragment.dropFirst(2))
        guard !value.isEmpty else { return nil }
        return value.removingPercentEncoding ?? value
    }
}
