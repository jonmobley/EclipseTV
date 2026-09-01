//
//  QuestPollModels.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One saved poll deck from `GET /api/polls`.
struct QuestPollSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let questionCount: Int
}

/// Envelope for `GET /api/polls`.
struct QuestPollListResponse: Codable, Equatable, Sendable {
    let polls: [QuestPollSummary]
}

/// Full deck from `GET /api/polls/:id` (Practice).
struct QuestPollDeck: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let questions: [QuestPollDeckQuestion]
}

/// One question in a Practice deck payload.
struct QuestPollDeckQuestion: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let text: String
    let options: [QuestPollDeckOption]
}

/// Answer choice in a Practice deck question.
struct QuestPollDeckOption: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let text: String
}

/// Envelope for `GET /api/polls/:id`.
struct QuestPollDeckResponse: Codable, Equatable, Sendable {
    let poll: QuestPollDeck
}

/// Current question payload on a live session (null in lobby).
struct QuestPollQuestion: Codable, Equatable, Sendable {
    let id: String?
    let text: String?
    let index: Int?
    let totalQuestions: Int?
}

/// Live room returned by session create / poll / control.
struct QuestPollSession: Codable, Equatable, Sendable {
    let id: String
    let code: String
    let pollId: String
    let pollTitle: String
    let mode: String
    let status: String
    let questionIndex: Int
    let voteCount: Int
    let isHost: Bool
    let isController: Bool
    /// Present when a question is open; omitted or null in lobby.
    let question: QuestPollQuestion?

    /// Prompt for the open question, if the API included one.
    var questionPrompt: String? {
        let text = question?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Deck length when the session payload carries `totalQuestions`.
    var resolvedQuestionCount: Int? {
        if let total = question?.totalQuestions, total > 0 { return total }
        return nil
    }
}

/// `{ "session": … }` from create / control / active.
struct QuestPollSessionEnvelope: Codable, Equatable, Sendable {
    let session: QuestPollSession?
}

/// Host PIN check or API error body.
struct QuestPollAPIError: Codable, Equatable, Sendable {
    let error: String?
    let ok: Bool?
}

/// Transport / PIN / control failures.
enum QuestPollError: Error, Equatable {
    case invalidPIN
    case server(String)
    case decoding
    case transport
}
