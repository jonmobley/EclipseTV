//
//  RemoteAPIClient.swift
//  EclipseRemoteProtocol
//
//  Description: HTTP + SSE client for the Eclipse LAN phone-remote protocol.
//               Uses Bearer auth on every request (no cookie jar required).
//  Thread Safety: Actor-isolated; safe to call from UI or background tasks.
//

import Foundation

// MARK: - Errors

/// Failures while talking to the Mac remote server.
public enum RemoteAPIError: Error, Equatable, Sendable {
    case invalidURL
    case unauthorized
    case rateLimited
    case pairWrongPIN(remaining: Int?)
    case pairLocked
    case pairNotArmed
    case server(message: String, status: Int)
    case decoding
    case disconnected
}

// MARK: - RemoteAPIClient

/// Thin client for `/session`, `/pair`, `/command`, `/events`, and `/thumb`.
///
/// Prefer keeping the session token in memory and sending
/// `Authorization: Bearer` on every call — including SSE — so the native app
/// does not depend on cookie storage.
///
/// Thread Safety: Actor-isolated.
public actor RemoteAPIClient {

    // MARK: - Properties

    public let baseURL: URL
    private let session: URLSession
    private var eventTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a client for one Mac remote origin.
    /// - Parameters:
    ///   - baseURL: Origin such as `http://eclipse.local:7878`.
    ///   - session: Injected for tests; defaults to ephemeral shared config.
    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Pairing

    /// Exchanges a QR bootstrap token for a confirmed session token.
    /// - Parameter bootstrapToken: Fragment token from `#t=…`.
    /// - Returns: The same token when `/session` accepts it.
    public func establishSession(bootstrapToken: String) async throws -> String {
        let url = try makeURL(path: "/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bootstrapToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        try throwIfFailed(response)
        return bootstrapToken
    }

    /// Pairs with a 6-digit PIN and returns the session token from Set-Cookie.
    /// - Parameter pin: Digits only (formatting spaces ignored by caller).
    /// - Returns: Session token for Bearer auth.
    public func pair(pin: String) async throws -> String {
        let url = try makeURL(path: "/pair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["pin": pin])
        let (data, response) = try await session.data(for: request)
        try throwIfPairFailed(data: data, response: response)
        // Prefer the response header; fall back to the cookie jar because
        // URLSession often strips Set-Cookie after storing HttpOnly cookies.
        if let token = SessionCookieParser.token(from: response) {
            return token
        }
        if let token = SessionCookieParser.token(
            from: session.configuration.httpCookieStorage,
            url: url
        ) {
            return token
        }
        throw RemoteAPIError.server(message: "missing session cookie", status: 500)
    }

    // MARK: - Commands & Thumbnails

    /// Sends a remote command.
    /// - Parameters:
    ///   - command: Action payload.
    ///   - token: Session Bearer token.
    public func send(command: RemoteCommand, token: String) async throws {
        let url = try makeURL(path: "/command")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(command)
        let (_, response) = try await session.data(for: request)
        try throwIfFailed(response)
    }

    /// Downloads a media thumbnail PNG.
    /// - Parameters:
    ///   - id: Media item UUID string.
    ///   - token: Session Bearer token.
    /// - Returns: PNG data.
    public func thumbnail(id: String, token: String) async throws -> Data {
        let url = try makeURL(path: "/thumb/\(id)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try throwIfFailed(response)
        return data
    }

    /// Lightweight auth check used before SSE reconnect (matches web remote).
    ///
    /// - Parameter token: Session Bearer token.
    /// - Returns: `false` only on HTTP 401; network blips return `true` so the
    ///   client retries. Any non-401 status (including 404 for the probe id)
    ///   means the session is still valid.
    public func probeSession(token: String) async -> Bool {
        do {
            let url = try makeURL(path: "/thumb/reconnect-probe")
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return true }
            return http.statusCode != 401
        } catch {
            return true
        }
    }

    // MARK: - Events

    /// Opens the SSE stream and yields decoded snapshots until cancelled.
    /// - Parameters:
    ///   - token: Session Bearer token.
    ///   - onSnapshot: Called on the cooperative thread for each event.
    public func listenForEvents(
        token: String,
        onSnapshot: @Sendable @escaping (RemoteStateSnapshot) -> Void
    ) async throws {
        eventTask?.cancel()
        let url = try makeURL(path: "/events")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // SSE is a long-lived stream; do not apply the short request timeout.
        request.timeoutInterval = 60 * 60 * 24

        let (bytes, response) = try await session.bytes(for: request)
        try throwIfFailed(response)

        // Parse raw chunks (not `bytes.lines`). Line iteration can stall on the
        // trailing blank line of `data: …\n\n` until another byte arrives, so the
        // first snapshot never flushes while the Mac is idle.
        var parser = SSEEventParser()
        let decoder = JSONDecoder()
        var iterator = bytes.makeAsyncIterator()
        var chunk = Data()
        chunk.reserveCapacity(4096)

        while let byte = try await iterator.next() {
            try Task.checkCancellation()
            chunk.append(byte)
            // Flush on SSE frame boundary or when the chunk grows large enough.
            if byte == UInt8(ascii: "\n") || chunk.count >= 4096 {
                let events = parser.push(chunk)
                chunk.removeAll(keepingCapacity: true)
                for json in events {
                    guard let payload = json.data(using: .utf8) else { continue }
                    do {
                        let snapshot = try decoder.decode(
                            RemoteStateSnapshot.self,
                            from: payload
                        )
                        onSnapshot(snapshot)
                    } catch {
                        throw RemoteAPIError.decoding
                    }
                }
            }
        }
        if !chunk.isEmpty {
            for json in parser.push(chunk) {
                guard let payload = json.data(using: .utf8),
                      let snapshot = try? decoder.decode(
                        RemoteStateSnapshot.self, from: payload
                      ) else {
                    throw RemoteAPIError.decoding
                }
                onSnapshot(snapshot)
            }
        }
        throw RemoteAPIError.disconnected
    }

    /// Cancels an in-flight SSE listen task started via a wrapping Task.
    public func cancelEvents() {
        eventTask?.cancel()
        eventTask = nil
    }

    // MARK: - Private Helpers

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RemoteAPIError.invalidURL
        }
        return url
    }

    private func throwIfFailed(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RemoteAPIError.server(message: "invalid response", status: 0)
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw RemoteAPIError.unauthorized
        case 429:
            throw RemoteAPIError.rateLimited
        default:
            throw RemoteAPIError.server(
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                status: http.statusCode
            )
        }
    }

    private func throwIfPairFailed(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RemoteAPIError.server(message: "invalid response", status: 0)
        }
        if (200..<300).contains(http.statusCode) { return }

        struct PairError: Decodable {
            let error: String
            let remaining: Int?
        }
        let body = try? JSONDecoder().decode(PairError.self, from: data)
        switch body?.error {
        case "wrong":
            throw RemoteAPIError.pairWrongPIN(remaining: body?.remaining)
        case "locked":
            throw RemoteAPIError.pairLocked
        case "not armed":
            throw RemoteAPIError.pairNotArmed
        default:
            if http.statusCode == 401 { throw RemoteAPIError.unauthorized }
            if http.statusCode == 429 { throw RemoteAPIError.rateLimited }
            throw RemoteAPIError.server(
                message: body?.error ?? "pair failed",
                status: http.statusCode
            )
        }
    }
}
