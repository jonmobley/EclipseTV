//
//  QuestPollDeckWriter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit

/// Saves and deletes the signed-in account's polls on QuestPoll.
///
/// `LivePollClient` (shared with the Mac) only reads polls; these are the
/// matching write calls (`POST` / `PUT` / `DELETE /api/polls`), the same ones
/// the website's editor uses. They belong in LivePollKit once the Mac's own
/// editor needs them too.
struct QuestPollDeckWriter: Sendable {

    var client: LivePollClient

    init(client: LivePollClient = LivePollAccountStore.client()) {
        self.client = client
    }

    /// Creates the poll (no `id`) or replaces the saved one, and returns it
    /// as stored, with its id.
    func save(_ deck: LivePollDeck) async throws -> LivePollDeck {
        var request = request(pollId: deck.id, method: deck.id == nil ? "POST" : "PUT")
        request.httpBody = try JSONEncoder().encode(deck)
        let data = try await data(for: request)
        struct Envelope: Decodable { let poll: LivePollDeck }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data).poll
        } catch {
            throw LivePollError.decoding
        }
    }

    /// Deletes a saved poll. A room already running it keeps its own copy.
    func delete(pollId: String) async throws {
        _ = try await data(for: request(pollId: pollId, method: "DELETE"))
    }

    // MARK: - Private

    private func request(pollId: String?, method: String) -> URLRequest {
        var url = client.origin
            .appendingPathComponent("api")
            .appendingPathComponent("polls")
        if let pollId { url = url.appendingPathComponent(pollId) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = client.accountToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await client.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LivePollError.transport
            }
            if (200...299).contains(http.statusCode) { return data }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw LivePollError.unauthorized
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["error"] as? String {
                throw LivePollError.server(message)
            }
            throw LivePollError.server("HTTP \(http.statusCode)")
        } catch let error as LivePollError {
            throw error
        } catch is CancellationError {
            throw LivePollError.cancelled
        } catch {
            throw LivePollError.transport
        }
    }
}
