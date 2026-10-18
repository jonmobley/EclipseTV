//
//  QuestPollSessionChange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit

/// How a Live Poll session update should refresh the Show UI.
enum QuestPollSessionChange: Equatable {
    /// Poll tick with no visible difference — skip notify.
    case none
    /// Vote count / join code on the card. Ribbon stays put.
    case tile
    /// Join / Question / Results cue or deck length. Ribbon thumbs only.
    case cue
    /// Room started, ended, or switched cards. Hero, grid, polling.
    case session
}

/// Fields that decide Live Poll chrome vs ribbon vs tile updates.
struct QuestPollSessionSnapshot: Equatable {
    var session: LivePollSession?
    var membershipId: UUID?
    var questionCount: Int
    var practiceMembershipId: UUID?
    /// Cue the Practice preview is on (no room).
    var practiceCueIndex: Int = 0
}

extension QuestPollSessionChange {

    /// Classifies a store update so poll ticks do not rebuild the ribbon.
    static func classify(
        from old: QuestPollSessionSnapshot,
        to new: QuestPollSessionSnapshot
    ) -> QuestPollSessionChange {
        if old == new { return .none }
        if old.session == nil, new.session == nil,
           old.membershipId == new.membershipId,
           old.practiceMembershipId == new.practiceMembershipId,
           old.questionCount == new.questionCount {
            return old.practiceCueIndex == new.practiceCueIndex ? .none : .cue
        }
        if isSessionChromeChange(from: old, to: new) { return .session }
        if cue(of: old) != cue(of: new) { return .cue }
        if answeredCount(of: old) != answeredCount(of: new)
            || joinedCount(of: old) != joinedCount(of: new)
            || old.session?.qa != new.session?.qa {
            return .tile
        }
        // Question payload / remainingMs can change every 2s status poll
        // without a visible tile or ribbon change.
        return .none
    }

    // MARK: - Private

    private static func isSessionChromeChange(
        from old: QuestPollSessionSnapshot,
        to new: QuestPollSessionSnapshot
    ) -> Bool {
        (old.session == nil) != (new.session == nil)
            || old.membershipId != new.membershipId
            || old.practiceMembershipId != new.practiceMembershipId
            || old.session?.joinCode != new.session?.joinCode
            || old.session?.deckTitle != new.session?.deckTitle
    }

    private static func cue(
        of snap: QuestPollSessionSnapshot
    ) -> (index: Int, count: Int) {
        let count = QuestPollRibbon.items(questionCount: snap.questionCount).count
        guard let session = snap.session else { return (snap.practiceCueIndex, count) }
        let index = QuestPollRibbon.currentIndex(
            phase: session.phase,
            questionIndex: session.questionIndex,
            questionCount: snap.questionCount
        )
        return (index, count)
    }

    private static func answeredCount(of snap: QuestPollSessionSnapshot) -> Int {
        snap.session?.answeredCount ?? 0
    }

    private static func joinedCount(of snap: QuestPollSessionSnapshot) -> Int {
        snap.session?.players.count ?? 0
    }
}
