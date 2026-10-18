//
//  QuestPollRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit
import Testing
@testable import EclipseiPhone

struct QuestPollRibbonTests {

    @Test func itemsAreJoinThenQuestionResultsPairs() {
        let items = QuestPollRibbon.items(questionCount: 2)
        #expect(items.map(\.title) == [
            "Join", "Question 1", "Results 1", "Question 2", "Results 2"
        ])
        #expect(items.map(\.cue) == [
            .join, .question(0), .results(0), .question(1), .results(1)
        ])
    }

    @Test func itemsKeepShortLabelsNotQuestionCopy() {
        let items = QuestPollRibbon.items(questionCount: 1)
        #expect(items.map(\.title) == ["Join", "Question 1", "Results 1"])
    }

    @Test func lobbyIsJoinCue() {
        #expect(
            QuestPollRibbon.currentIndex(
                phase: .lobby, questionIndex: 0, questionCount: 3
            ) == 0
        )
    }

    @Test func liveQuestionMapsToQuestionCue() {
        #expect(
            QuestPollRibbon.currentIndex(
                phase: .questionOpen, questionIndex: 1, questionCount: 3
            ) == 3
        )
    }

    @Test func resultsMapsToResultsCue() {
        #expect(
            QuestPollRibbon.currentIndex(
                phase: .reveal, questionIndex: 0, questionCount: 3
            ) == 2
        )
    }

    @Test func leaderboardAndEndCountAsResults() {
        #expect(
            QuestPollRibbon.currentIndex(
                phase: .leaderboard, questionIndex: 1, questionCount: 3
            ) == 4
        )
        #expect(
            QuestPollRibbon.currentIndex(
                phase: .ended, questionIndex: 2, questionCount: 3
            ) == 6
        )
    }

    /// Regression: going back used to send one `prev` per cue, but the relay's
    /// `prev` jumps to the previous question's results, so Results 2 → Question 2
    /// landed on Results 1. The shared plan reopens Question 2 directly.
    @Test func backFromResultsToTheSameQuestionReopensIt() throws {
        let plan = try #require(LivePollCues.plan(
            phase: .reveal, questionIndex: 1, questionCount: 3, to: .question(1)
        ))
        #expect(plan.commands == [.startQuestion(index: 1)])
        #expect(plan.reopensQuestion)
    }

    @Test func ribbonTracksOnProgramOrPracticeNotALeftoverRoom() {
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: false,
            isPracticing: true
        ))
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: true,
            isPracticing: false
        ))
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: false,
            isPracticing: false
        ) == false)
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: false,
            liveRoomActive: true,
            isPracticing: true
        ) == false)
    }

    @Test func currentCueIsLiveOnlyOnProgramOrPractice() {
        #expect(QuestPollRibbon.cueIsLive(
            index: 2, currentIndex: 2,
            pollIsOnProgram: true, isPracticing: false
        ))
        #expect(QuestPollRibbon.cueIsLive(
            index: 0, currentIndex: 0,
            pollIsOnProgram: false, isPracticing: true
        ))
        #expect(QuestPollRibbon.cueIsLive(
            index: 0, currentIndex: 0,
            pollIsOnProgram: false, isPracticing: false
        ) == false)
        #expect(QuestPollRibbon.cueIsLive(
            index: 1, currentIndex: 2,
            pollIsOnProgram: true, isPracticing: false
        ) == false)
    }
}
