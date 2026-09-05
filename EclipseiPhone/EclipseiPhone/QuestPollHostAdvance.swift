//
//  QuestPollHostAdvance.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Primary host-controller button for one ribbon step forward.
struct QuestPollHostAdvance: Equatable {
    var title: String
    var action: String
}

extension QuestPollHostAdvance {

    /// Mirrors questpoll.live `/host/controller` primary control labels.
    static func primary(
        status: String,
        questionIndex: Int,
        questionCount: Int
    ) -> QuestPollHostAdvance? {
        let count = max(questionCount, 1)
        let index = min(max(questionIndex, 0), count - 1)
        switch status.lowercased() {
        case "lobby", "join", "waiting":
            return QuestPollHostAdvance(title: "Open question 1", action: "start")
        case "voting", "locked", "question":
            return QuestPollHostAdvance(title: "Show results", action: "results")
        case "results", "reveal", "score":
            if index >= count - 1 {
                return QuestPollHostAdvance(title: "Finish poll", action: "next")
            }
            return QuestPollHostAdvance(title: "Next question", action: "next")
        case "ended", "complete", "done":
            return nil
        default:
            return QuestPollHostAdvance(title: "Show results", action: "results")
        }
    }

    /// Progress line under the Responses card.
    static func progressLabel(questionIndex: Int, questionCount: Int) -> String {
        let count = max(questionCount, 1)
        let display = min(max(questionIndex, 0), count - 1) + 1
        return "Question \(display) of \(count)"
    }

    /// Projector join-QR overlay while a question or results is up.
    static func joinQRToggle(
        status: String,
        isVisible: Bool
    ) -> QuestPollHostAdvance? {
        switch status.lowercased() {
        case "lobby", "join", "waiting", "ended", "complete", "done":
            return nil
        default:
            if isVisible {
                return QuestPollHostAdvance(title: "Hide QR", action: "hideqr")
            }
            return QuestPollHostAdvance(title: "Show QR", action: "showqr")
        }
    }
}
