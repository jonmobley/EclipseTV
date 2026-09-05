//
//  QuestPollSessionChange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

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
    var session: QuestPollSession?
    var membershipId: UUID?
    var questionCount: Int
    var practiceMembershipId: UUID?
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
            return .none
        }
        if isSessionChromeChange(from: old, to: new) { return .session }
        if cue(of: old) != cue(of: new) { return .cue }
        if voteCount(of: old) != voteCount(of: new) { return .tile }
        // Question payload / host flags can change every 2s status poll
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
            || old.session?.id != new.session?.id
            || old.session?.code != new.session?.code
            || old.session?.pollId != new.session?.pollId
    }

    private static func cue(
        of snap: QuestPollSessionSnapshot
    ) -> (index: Int, count: Int) {
        let count = QuestPollRibbon.items(questionCount: snap.questionCount).count
        guard let session = snap.session else { return (0, count) }
        let index = QuestPollRibbon.currentIndex(
            status: session.status,
            questionIndex: session.questionIndex,
            questionCount: snap.questionCount
        )
        return (index, count)
    }

    private static func voteCount(of snap: QuestPollSessionSnapshot) -> Int {
        snap.session?.voteCount ?? 0
    }
}
