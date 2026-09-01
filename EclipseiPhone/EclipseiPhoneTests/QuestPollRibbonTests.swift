//
//  QuestPollRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct QuestPollRibbonTests {

    @Test func itemsAreJoinThenQuestionResultsPairs() {
        let items = QuestPollRibbon.items(questionCount: 2)
        #expect(items.map(\.title) == [
            "Join", "Question 1", "Results 1", "Question 2", "Results 2"
        ])
        #expect(items.map(\.kind) == [
            .join, .question(0), .results(0), .question(1), .results(1)
        ])
    }

    @Test func itemsUsePromptWhenProvided() {
        let items = QuestPollRibbon.items(
            questionCount: 1,
            prompts: [0: "How long?"]
        )
        #expect(items.map(\.title) == ["Join", "How long?", "Results 1"])
    }

    @Test func lobbyIsJoinCue() {
        #expect(
            QuestPollRibbon.currentIndex(
                status: "lobby", questionIndex: 0, questionCount: 3
            ) == 0
        )
    }

    @Test func liveQuestionMapsToQuestionCue() {
        #expect(
            QuestPollRibbon.currentIndex(
                status: "question", questionIndex: 1, questionCount: 3
            ) == 3
        )
    }

    @Test func resultsMapsToResultsCue() {
        #expect(
            QuestPollRibbon.currentIndex(
                status: "results", questionIndex: 0, questionCount: 3
            ) == 2
        )
    }

    @Test func forwardFromJoinToFirstQuestionIsStart() {
        #expect(
            QuestPollRibbon.forwardActions(
                from: 0, to: 1, questionCount: 2
            ) == ["start"]
        )
    }

    @Test func forwardFromQuestionToItsResultsIsResults() {
        #expect(
            QuestPollRibbon.forwardActions(
                from: 1, to: 2, questionCount: 2
            ) == ["results"]
        )
    }

    @Test func jumpJoinToSecondQuestionChains() {
        #expect(
            QuestPollRibbon.forwardActions(
                from: 0, to: 3, questionCount: 2
            ) == ["start", "results", "next"]
        )
    }

    @Test func forwardBackwardProducesNoActions() {
        #expect(
            QuestPollRibbon.forwardActions(
                from: 2, to: 0, questionCount: 2
            ).isEmpty
        )
    }

    @Test func backwardFromResultsToQuestionIsPrev() {
        #expect(
            QuestPollRibbon.backwardActions(
                from: 2, to: 1, questionCount: 2
            ) == ["prev"]
        )
    }

    @Test func backwardFromQuestionToJoinChainsPrev() {
        #expect(
            QuestPollRibbon.backwardActions(
                from: 1, to: 0, questionCount: 2
            ) == ["prev"]
        )
    }

    @Test func backwardOnJoinIsEmpty() {
        #expect(
            QuestPollRibbon.backwardActions(
                from: 0, to: 0, questionCount: 2
            ).isEmpty
        )
    }

    @Test func ribbonShowsOnGateAndPracticeBeforeLiveRoom() {
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: false,
            isPracticing: false,
            isGated: true
        ))
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: false,
            isPracticing: true,
            isGated: false
        ))
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: true,
            isPracticing: false,
            isGated: false
        ))
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: true,
            liveRoomActive: false,
            isPracticing: false,
            isGated: false
        ) == false)
        #expect(QuestPollRibbon.shouldShow(
            isShowMode: false,
            liveRoomActive: true,
            isPracticing: true,
            isGated: true
        ) == false)
    }
}
