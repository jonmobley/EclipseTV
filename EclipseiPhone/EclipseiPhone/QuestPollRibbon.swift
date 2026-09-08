//
//  QuestPollRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit

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

/// Builds and advances the Live Poll ribbon from session phase.
enum QuestPollRibbon {

    /// Join / Question / Results strip while the poll is on program, in
    /// Practice, or on the Start gate. A leftover room after the user switched
    /// to a photo is not `liveRoomActive`.
    static func shouldShow(
        isShowMode: Bool,
        liveRoomActive: Bool,
        isPracticing: Bool,
        isGated: Bool
    ) -> Bool {
        isShowMode && (liveRoomActive || isPracticing || isGated)
    }

    /// Red live stroke on the current cue while on program or Practice, never the gate.
    static func cueIsLive(
        index: Int,
        currentIndex: Int,
        pollIsOnProgram: Bool,
        isPracticing: Bool
    ) -> Bool {
        index == currentIndex && (pollIsOnProgram || isPracticing)
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
        phase: LivePollPhase,
        questionIndex: Int,
        questionCount: Int
    ) -> Int {
        let items = items(questionCount: questionCount)
        let kind = kind(phase: phase, questionIndex: questionIndex, count: questionCount)
        return items.firstIndex { $0.kind == kind } ?? 0
    }

    /// Host commands to walk forward from `currentIndex` to `targetIndex`.
    static func forwardCommands(
        from currentIndex: Int,
        to targetIndex: Int,
        questionCount: Int
    ) -> [LivePollHostCommand] {
        guard targetIndex > currentIndex else { return [] }
        let items = items(questionCount: questionCount)
        let last = items.count - 1
        var commands: [LivePollHostCommand] = []
        var index = currentIndex
        while index < targetIndex, items.indices.contains(index) {
            guard let command = forwardCommand(from: items[index], isLast: index == last)
            else { break }
            commands.append(command)
            index += 1
        }
        return commands
    }

    /// Host commands to walk backward (`prev`) from `currentIndex` to `target`.
    static func backwardCommands(
        from currentIndex: Int,
        to targetIndex: Int,
        questionCount: Int
    ) -> [LivePollHostCommand] {
        guard targetIndex < currentIndex else { return [] }
        var commands: [LivePollHostCommand] = []
        var index = currentIndex
        while index > targetIndex {
            commands.append(.prev)
            index -= 1
        }
        return commands
    }

    // MARK: - Private

    private static func kind(
        phase: LivePollPhase,
        questionIndex: Int,
        count: Int
    ) -> QuestPollRibbonItem.Kind {
        let clamped = min(max(questionIndex, 0), max(count - 1, 0))
        switch phase {
        case .lobby:
            return .join
        case .reveal, .leaderboard:
            return .results(clamped)
        case .ended:
            return .results(max(count - 1, 0))
        case .questionOpen, .locked:
            return .question(clamped)
        }
    }

    private static func forwardCommand(
        from item: QuestPollRibbonItem,
        isLast: Bool
    ) -> LivePollHostCommand? {
        switch item.kind {
        case .join: return .startQuestion(index: 0)
        case .question: return .reveal
        case .results: return isLast ? nil : .next
        }
    }
}
