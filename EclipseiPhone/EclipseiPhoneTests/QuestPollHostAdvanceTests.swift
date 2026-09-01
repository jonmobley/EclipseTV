//
//  QuestPollHostAdvanceTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct QuestPollHostAdvanceTests {

    @Test func lobbyOpensFirstQuestion() {
        #expect(
            QuestPollHostAdvance.primary(
                status: "lobby", questionIndex: 0, questionCount: 6
            ) == QuestPollHostAdvance(title: "Open question 1", action: "start")
        )
    }

    @Test func votingShowsResults() {
        #expect(
            QuestPollHostAdvance.primary(
                status: "voting", questionIndex: 1, questionCount: 6
            ) == QuestPollHostAdvance(title: "Show results", action: "results")
        )
    }

    @Test func midResultsGoesNext() {
        #expect(
            QuestPollHostAdvance.primary(
                status: "results", questionIndex: 1, questionCount: 6
            ) == QuestPollHostAdvance(title: "Next question", action: "next")
        )
    }

    @Test func lastResultsFinishes() {
        #expect(
            QuestPollHostAdvance.primary(
                status: "results", questionIndex: 5, questionCount: 6
            ) == QuestPollHostAdvance(title: "Finish poll", action: "next")
        )
    }

    @Test func progressLabelIsOneBased() {
        #expect(
            QuestPollHostAdvance.progressLabel(
                questionIndex: 1, questionCount: 6
            ) == "Question 2 of 6"
        )
    }

    @Test func joinURLIncludesCode() throws {
        let url = QuestPollConfig.joinURL(code: "VR2V")
        #expect(url.absoluteString.contains("code=VR2V"))
        #expect(url.host == "questpoll.live")
    }
}
