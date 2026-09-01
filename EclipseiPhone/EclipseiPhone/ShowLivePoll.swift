//
//  ShowLivePoll.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A named QuestPoll deck card in a Show.
struct ShowLivePoll: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    /// Show (`LocalAlbum`) this card belongs to.
    var showId: UUID
    /// QuestPoll deck id (`poll-1`, …).
    var pollId: String
    var title: String
    /// Deck length from the picker / list API.
    var questionCount: Int
    let createdAt: Date

    /// Creates a Live Poll card bound to `pollId`.
    init(
        id: UUID = UUID(),
        showId: UUID,
        pollId: String,
        title: String,
        questionCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showId = showId
        self.pollId = pollId
        self.title = title
        self.questionCount = max(questionCount, 1)
        self.createdAt = createdAt
    }

    /// Tile caption: deck title, optionally with live subtitle.
    func tileTitle(subtitle: String? = nil) -> String {
        if let subtitle, !subtitle.isEmpty {
            return "\(title)\n\(subtitle)"
        }
        return title
    }
}
