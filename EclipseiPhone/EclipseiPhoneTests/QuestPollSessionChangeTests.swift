//
//  QuestPollSessionChangeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit
import Testing
@testable import EclipseiPhone

struct QuestPollSessionChangeTests {

    @Test func identicalSnapshotsAreNone() {
        let session = makeSession(phase: .lobby, questionIndex: 0, answeredCount: 2)
        let snap = QuestPollSessionSnapshot(
            session: session,
            membershipId: UUID(),
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: snap, to: snap) == .none)
    }

    @Test func questionPayloadOnlyIsNone() {
        let membership = UUID()
        let old = QuestPollSessionSnapshot(
            session: makeSession(phase: .questionOpen, questionIndex: 0, answeredCount: 2),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        let new = QuestPollSessionSnapshot(
            session: makeSession(
                phase: .questionOpen,
                questionIndex: 0,
                answeredCount: 2,
                question: LivePollPublicQuestion(
                    id: "q1",
                    prompt: "How long?",
                    options: [],
                    timeLimitSeconds: 30
                )
            ),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: old, to: new) == .none)
    }

    @Test func answerOnlyChangeIsTile() {
        let membership = UUID()
        let old = QuestPollSessionSnapshot(
            session: makeSession(phase: .questionOpen, questionIndex: 0, answeredCount: 1),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        let new = QuestPollSessionSnapshot(
            session: makeSession(phase: .questionOpen, questionIndex: 0, answeredCount: 4),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: old, to: new) == .tile)
    }

    @Test func phaseCueChangeIsCue() {
        let membership = UUID()
        let old = QuestPollSessionSnapshot(
            session: makeSession(phase: .lobby, questionIndex: 0, answeredCount: 0),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        let new = QuestPollSessionSnapshot(
            session: makeSession(phase: .questionOpen, questionIndex: 0, answeredCount: 0),
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
            session: makeSession(phase: .lobby, questionIndex: 0, answeredCount: 0),
            membershipId: membership,
            questionCount: 3,
            practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: old, to: new) == .session)
    }

    @Test @MainActor
    func adoptSkipsNotifyWhenUnchanged() {
        let store = QuestPollSessionStore()
        let session = makeSession(phase: .lobby, questionIndex: 0, answeredCount: 0)
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
        phase: LivePollPhase,
        questionIndex: Int,
        answeredCount: Int,
        question: LivePollPublicQuestion? = nil
    ) -> LivePollSession {
        LivePollSession(
            phase: phase,
            joinCode: "ABCD",
            deckTitle: "Session 1",
            questionIndex: questionIndex,
            questionCount: 3,
            question: question,
            answeredCount: answeredCount
        )
    }
}
