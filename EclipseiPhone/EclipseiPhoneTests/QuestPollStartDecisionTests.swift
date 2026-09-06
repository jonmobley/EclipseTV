//
//  QuestPollStartDecisionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct QuestPollStartDecisionTests {

    @Test func startsWhenNothingIsRunning() {
        #expect(
            QuestPollStartDecision.decide(
                hasLocalSession: false, active: nil, pollId: "poll-1"
            ) == .start
        )
    }

    @Test func resumesTheSameDeckLeftRunningElsewhere() {
        let active = session(pollId: "poll-1", status: "voting")
        #expect(
            QuestPollStartDecision.decide(
                hasLocalSession: false, active: active, pollId: "poll-1"
            ) == .resume(active)
        )
    }

    @Test func offersReplaceWhenAnotherDeckIsLive() {
        let active = session(pollId: "poll-2", status: "lobby")
        #expect(
            QuestPollStartDecision.decide(
                hasLocalSession: false, active: active, pollId: "poll-1"
            ) == .replace(running: active)
        )
    }

    @Test func localRoomAlwaysAsksToReplace() {
        let active = session(pollId: "poll-1", status: "voting")
        #expect(
            QuestPollStartDecision.decide(
                hasLocalSession: true, active: active, pollId: "poll-1"
            ) == .replace(running: nil)
        )
    }

    @Test func finishedRoomDoesNotBlockStart() {
        let done = session(pollId: "poll-1", status: "done")
        #expect(
            QuestPollStartDecision.decide(
                hasLocalSession: false, active: done, pollId: "poll-1"
            ) == .start
        )
    }

    private func session(pollId: String, status: String) -> QuestPollSession {
        QuestPollSession(
            id: "sess-1",
            code: "ABCD",
            pollId: pollId,
            pollTitle: "Deck",
            mode: "live",
            status: status,
            questionIndex: 0,
            voteCount: 0,
            isHost: true,
            isController: true,
            question: nil,
            joinQrVisible: nil
        )
    }
}
