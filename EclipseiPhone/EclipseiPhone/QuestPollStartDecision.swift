//
//  QuestPollStartDecision.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// What tapping Start on a Live Poll card should do, given what is already
/// running locally and on the server.
///
/// The server keeps one PIN room "active" for every PIN holder, so a room
/// started by another device (or by this phone before a relaunch) is found by
/// `GET /api/sessions?active=1`. Joining it is preferred over ending it.
enum QuestPollStartDecision: Equatable {
    /// No room anywhere: create one.
    case start
    /// The active room already runs this card's deck: adopt it as our own.
    case resume(QuestPollSession)
    /// A room is live (locally or elsewhere). `running` is the server room
    /// when it is not ours; nil when the local store owns the room.
    case replace(running: QuestPollSession?)

    /// Chooses between starting, resuming, or replacing.
    ///
    /// - Parameters:
    ///   - hasLocalSession: This phone already owns a room in memory.
    ///   - active: Server's active PIN room, if any (finished rooms are
    ///     reported as nil by the server for hosts).
    ///   - pollId: Deck bound to the tapped card.
    static func decide(
        hasLocalSession: Bool,
        active: QuestPollSession?,
        pollId: String
    ) -> QuestPollStartDecision {
        if hasLocalSession { return .replace(running: nil) }
        guard let active, !isFinished(active) else { return .start }
        if active.pollId == pollId { return .resume(active) }
        return .replace(running: active)
    }

    private static func isFinished(_ session: QuestPollSession) -> Bool {
        switch session.status.lowercased() {
        case "done", "ended", "complete": return true
        default: return false
        }
    }
}
