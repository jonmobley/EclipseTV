//
//  QuestPollSessionChangeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct QuestPollSessionChangeTests {

    @Test func identicalSnapshotsAreNone() {
        let session = makeSession(status: "lobby", questionIndex: 0, voteCount: 2)
        let snap = QuestPollSessionSnapshot(
            session: session,
            membershipId: UUID(),
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: snap, to: snap) == .none)
    }

    @Test func voteOnlyChangeIsTile() {
        let membership = UUID()
        let old = QuestPollSessionSnapshot(
            session: makeSession(status: "question", questionIndex: 0, voteCount: 1),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        let new = QuestPollSessionSnapshot(
            session: makeSession(status: "question", questionIndex: 0, voteCount: 4),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: old, to: new) == .tile)
    }

    @Test func statusCueChangeIsCue() {
        let membership = UUID()
        let old = QuestPollSessionSnapshot(
            session: makeSession(status: "lobby", questionIndex: 0, voteCount: 0),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        let new = QuestPollSessionSnapshot(
            session: makeSession(status: "question", questionIndex: 0, voteCount: 0),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: old, to: new) == .cue)
    }

    @Test func roomStartIsSession() {
        let membership = UUID()
        let old = QuestPollSessionSnapshot(
            session: nil,
            membershipId: nil,
            questionCount: 1,
            practiceMembershipId: nil
        )
        let new = QuestPollSessionSnapshot(
            session: makeSession(status: "lobby", questionIndex: 0, voteCount: 0),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: old, to: new) == .session)
    }

    @Test @MainActor
    func adoptSkipsNotifyWhenUnchanged() {
        let store = QuestPollSessionStore()
        let session = makeSession(status: "lobby", questionIndex: 0, voteCount: 0)
        let first = store.adopt(session, questionCount: 2, membershipId: UUID())
        #expect(first == .session)

        var sawNotify = false
        let token = NotificationCenter.default.addObserver(
            forName: QuestPollSessionStore.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            sawNotify = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let second = store.adopt(session, questionCount: 2)
        #expect(second == .none)
        #expect(sawNotify == false)
    }

    // MARK: - Fixtures

    private func makeSession(
        status: String,
        questionIndex: Int,
        voteCount: Int
    ) -> QuestPollSession {
        QuestPollSession(
            id: "sess-1",
            code: "ABCD",
            pollId: "poll-1",
            pollTitle: "Session 1",
            mode: "live",
            status: status,
            questionIndex: questionIndex,
            voteCount: voteCount,
            isHost: true,
            isController: true,
            question: nil
        )
    }
}
