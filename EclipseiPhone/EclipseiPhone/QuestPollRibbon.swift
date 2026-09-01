//
//  QuestPollRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One cue in the live-poll ribbon: Join, then Question / Results per item.
struct QuestPollRibbonItem: Equatable {
    enum Kind: Equatable {
        case join
        case question(Int)
        case results(Int)
    }

    var kind: Kind
    var title: String
    var systemImage: String
}

/// Builds and advances the Live Poll ribbon from session status.
enum QuestPollRibbon {

    /// Join / Question / Results strip: live room, Practice, or the Start gate.
    static func shouldShow(
        isShowMode: Bool,
        liveRoomActive: Bool,
        isPracticing: Bool,
        isGated: Bool
    ) -> Bool {
        isShowMode && (liveRoomActive || isPracticing || isGated)
    }

    /// Join, then Question n / Results n for each question.
    ///
    /// Ribbon thumbs stay short labels. Question copy belongs on the projector.
    static func items(questionCount: Int) -> [QuestPollRibbonItem] {
        let count = max(questionCount, 1)
        var items = [
            QuestPollRibbonItem(
                kind: .join, title: "Join", systemImage: "qrcode"
            )
        ]
        for index in 0..<count {
            items.append(QuestPollRibbonItem(
                kind: .question(index),
                title: "Question \(index + 1)",
                systemImage: "text.bubble.fill"
            ))
            items.append(QuestPollRibbonItem(
                kind: .results(index),
                title: "Results \(index + 1)",
                systemImage: "chart.bar.fill"
            ))
        }
        return items
    }

    /// Ribbon index for `session` (Join while in the lobby).
    static func currentIndex(
        status: String,
        questionIndex: Int,
        questionCount: Int
    ) -> Int {
        let items = items(questionCount: questionCount)
        let kind = kind(status: status, questionIndex: questionIndex, count: questionCount)
        return items.firstIndex { $0.kind == kind } ?? 0
    }

    /// Host control actions to walk forward from `currentIndex` to `targetIndex`.
    static func forwardActions(
        from currentIndex: Int,
        to targetIndex: Int,
        questionCount: Int
    ) -> [String] {
        guard targetIndex > currentIndex else { return [] }
        let items = items(questionCount: questionCount)
        let last = items.count - 1
        var actions: [String] = []
        var index = currentIndex
        while index < targetIndex, items.indices.contains(index) {
            guard let action = forwardAction(from: items[index], isLast: index == last)
            else { break }
            actions.append(action)
            index += 1
        }
        return actions
    }

    /// Host control actions to walk backward (`prev`) from `currentIndex` to `target`.
    static func backwardActions(
        from currentIndex: Int,
        to targetIndex: Int,
        questionCount: Int
    ) -> [String] {
        guard targetIndex < currentIndex else { return [] }
        var actions: [String] = []
        var index = currentIndex
        while index > targetIndex {
            actions.append("prev")
            index -= 1
        }
        return actions
    }

    // MARK: - Private

    private static func kind(
        status: String,
        questionIndex: Int,
        count: Int
    ) -> QuestPollRibbonItem.Kind {
        let clamped = min(max(questionIndex, 0), max(count - 1, 0))
        switch status.lowercased() {
        case "lobby", "join", "waiting":
            return .join
        case "results", "reveal", "score":
            return .results(clamped)
        case "ended", "complete", "done":
            return .results(max(count - 1, 0))
        case "voting", "locked", "question":
            return .question(clamped)
        default:
            return .question(clamped)
        }
    }

    private static func forwardAction(
        from item: QuestPollRibbonItem,
        isLast: Bool
    ) -> String? {
        switch item.kind {
        case .join: return "start"
        case .question: return "results"
        case .results: return isLast ? nil : "next"
        }
    }
}
