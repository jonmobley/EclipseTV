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
        #expect(items.map(\.kind) == [
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

    @Test func forwardFromJoinToFirstQuestionIsStart() {
        #expect(
            QuestPollRibbon.forwardCommands(
                from: 0, to: 1, questionCount: 2
            ) == [.startQuestion(index: 0)]
        )
    }

    @Test func forwardFromQuestionToItsResultsIsReveal() {
        #expect(
            QuestPollRibbon.forwardCommands(
                from: 1, to: 2, questionCount: 2
            ) == [.reveal]
        )
    }

    @Test func jumpJoinToSecondQuestionChains() {
        #expect(
            QuestPollRibbon.forwardCommands(
                from: 0, to: 3, questionCount: 2
            ) == [.startQuestion(index: 0), .reveal, .next]
        )
    }

    @Test func forwardBackwardProducesNoCommands() {
        #expect(
            QuestPollRibbon.forwardCommands(
                from: 2, to: 0, questionCount: 2
            ).isEmpty
        )
    }

    @Test func backwardFromResultsToQuestionIsPrev() {
        #expect(
            QuestPollRibbon.backwardCommands(
                from: 2, to: 1, questionCount: 2
            ) == [.prev]
        )
    }

    @Test func backwardFromQuestionToJoinChainsPrev() {
        #expect(
            QuestPollRibbon.backwardCommands(
                from: 1, to: 0, questionCount: 2
            ) == [.prev]
        )
    }

    @Test func backwardOnJoinIsEmpty() {
        #expect(
            QuestPollRibbon.backwardCommands(
                from: 0, to: 0, questionCount: 2
            ).isEmpty
        )
    }

    @Test func ribbonTracksOnProgramPracticeOrGateNotALeftoverRoom() {
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
