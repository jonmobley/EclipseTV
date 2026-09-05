//
//  QuestPollClient.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// HTTPS client for questpoll.live (PIN, decks, sessions, host control).
///
/// Expected control actions: `start`, `results`, `next`, `prev`, `end`,
/// `showqr`, `hideqr`.
/// Missing actions on the server surface as `QuestPollError.server`.
struct QuestPollClient: Sendable {
    var origin: URL
    var session: URLSession

    /// Live production origin.
    init(
        origin: URL = QuestPollConfig.origin,
        session: URLSession = .shared
    ) {
        self.origin = origin
        self.session = session
    }

    /// `POST /api/host` — `{ "ok": true }` or `{ "error": "Wrong PIN" }`.
    func verifyPIN(_ pin: String) async throws {
        let body = try JSONEncoder().encode(["pin": pin])
        var request = urlRequest(["api", "host"], method: "POST", pin: nil, hostId: nil)
        request.httpBody = body
        let data = try await data(for: request)
        let decoded = try JSONDecoder().decode(QuestPollAPIError.self, from: data)
        if decoded.ok == true { return }
        if decoded.error?.localizedCaseInsensitiveContains("pin") == true {
            throw QuestPollError.invalidPIN
        }
        throw QuestPollError.server(decoded.error ?? "Could not verify PIN")
    }

    /// `GET /api/polls` (sends host PIN when linked for account-scoped decks).
    func listPolls(pin: String? = nil, hostId: String? = nil) async throws
        -> [QuestPollSummary]
    {
        let request = urlRequest(
            ["api", "polls"], method: "GET", pin: pin, hostId: hostId
        )
        let data = try await data(for: request)
        do {
            return try JSONDecoder().decode(QuestPollListResponse.self, from: data)
                .polls
        } catch {
            throw QuestPollError.decoding
        }
    }

    /// `GET /api/polls/:id` — full deck for Practice (public).
    func poll(id: String) async throws -> QuestPollDeck {
        let request = urlRequest(
            ["api", "polls", id], method: "GET", pin: nil, hostId: nil
        )
        let data = try await data(for: request)
        do {
            return try JSONDecoder().decode(QuestPollDeckResponse.self, from: data)
                .poll
        } catch {
            throw QuestPollError.decoding
        }
    }

    /// `GET /api/sessions?active=1` — current room for this host, or nil.
    func activeSession(pin: String, hostId: String) async throws -> QuestPollSession? {
        var url = origin.appendingPathComponent("api")
            .appendingPathComponent("sessions")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "active", value: "1")]
        url = components.url ?? url
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(pin, forHTTPHeaderField: "x-host-pin")
        request.setValue(hostId, forHTTPHeaderField: "x-host-id")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data = try await data(for: request)
        let envelope = try JSONDecoder().decode(
            QuestPollSessionEnvelope.self, from: data
        )
        return envelope.session
    }

    /// `GET /api/sessions/:code` — live status / vote count for the ribbon.
    func fetchSession(
        joinCode: String,
        pin: String,
        hostId: String
    ) async throws -> QuestPollSession {
        let request = urlRequest(
            ["api", "sessions", joinCode],
            method: "GET",
            pin: pin,
            hostId: hostId
        )
        return try await decodeSession(from: request)
    }

    /// `POST /api/sessions` with `{ pollId, mode }`.
    func startSession(
        pollId: String,
        pin: String,
        hostId: String,
        mode: String = "live"
    ) async throws -> QuestPollSession {
        let body = try JSONEncoder().encode(["pollId": pollId, "mode": mode])
        var request = urlRequest(
            ["api", "sessions"], method: "POST", pin: pin, hostId: hostId
        )
        request.httpBody = body
        return try await decodeSession(from: request)
    }

    /// `POST /api/sessions/:code/control` with `{ action }`.
    ///
    /// Actions: `start` / `results` / `next` / `prev` / `end` /
    /// `showqr` / `hideqr`.
    /// The path key is the join code (e.g. `VR2V`), not the session UUID.
    func control(
        joinCode: String,
        action: String,
        pin: String,
        hostId: String
    ) async throws -> QuestPollSession {
        let body = try JSONEncoder().encode(["action": action])
        var request = urlRequest(
            ["api", "sessions", joinCode, "control"],
            method: "POST",
            pin: pin,
            hostId: hostId
        )
        request.httpBody = body
        return try await decodeSession(from: request)
    }

    // MARK: - Private

    private func urlRequest(
        _ path: [String],
        method: String,
        pin: String?,
        hostId: String?
    ) -> URLRequest {
        var url = origin
        for component in path {
            url = url.appendingPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let pin { request.setValue(pin, forHTTPHeaderField: "x-host-pin") }
        if let hostId { request.setValue(hostId, forHTTPHeaderField: "x-host-id") }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw QuestPollError.transport
            }
            if (200...299).contains(http.statusCode) { return data }
            if let api = try? JSONDecoder().decode(
                QuestPollAPIError.self, from: data
            ), let message = api.error {
                if message.localizedCaseInsensitiveContains("pin") {
                    throw QuestPollError.invalidPIN
                }
                throw QuestPollError.server(message)
            }
            throw QuestPollError.server("HTTP \(http.statusCode)")
        } catch let error as QuestPollError {
            throw error
        } catch {
            throw QuestPollError.transport
        }
    }

    private func decodeSession(from request: URLRequest) async throws
        -> QuestPollSession
    {
        let data = try await data(for: request)
        do {
            let envelope = try JSONDecoder().decode(
                QuestPollSessionEnvelope.self, from: data
            )
            guard let session = envelope.session else { throw QuestPollError.decoding }
            return session
        } catch let error as QuestPollError {
            throw error
        } catch {
            throw QuestPollError.decoding
        }
    }
}
