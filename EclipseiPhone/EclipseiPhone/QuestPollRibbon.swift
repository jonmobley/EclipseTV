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
    var cue: LivePollCue
    var title: String
    var systemImage: String
}

/// Live Poll ribbon for the Show screen. Cue order and the commands that reach
/// a cue come from LivePollKit's `LivePollCues`, shared with the Mac.
enum QuestPollRibbon {

    /// Join / Question / Results strip while the poll is on program or in
    /// Practice. A leftover room after the user switched to a photo is not
    /// `liveRoomActive`.
    static func shouldShow(
        isShowMode: Bool,
        liveRoomActive: Bool,
        isPracticing: Bool
    ) -> Bool {
        isShowMode && (liveRoomActive || isPracticing)
    }

    /// Red live stroke on the current cue while on program or in Practice.
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
        LivePollCues.strip(questionCount: questionCount).map { cue in
            QuestPollRibbonItem(cue: cue, title: cue.title, systemImage: symbol(for: cue))
        }
    }

    /// Ribbon index for the room (Join while in the lobby).
    static func currentIndex(
        phase: LivePollPhase,
        questionIndex: Int,
        questionCount: Int
    ) -> Int {
        LivePollCues.current(
            phase: phase,
            questionIndex: questionIndex,
            questionCount: questionCount
        ).index
    }

    private static func symbol(for cue: LivePollCue) -> String {
        switch cue {
        case .join: return "qrcode"
        case .question: return "text.bubble.fill"
        case .results: return "chart.bar.fill"
        }
    }
}
