//
//  QuestPollQATests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit
import Testing
@testable import EclipseiPhone

@MainActor
struct QuestPollQATests {

    private func qaSession(_ questions: String, featured: String = "null") throws -> LivePollSession {
        let json = """
        {"phase":"lobby","joinCode":"QA1234","mode":"qa","deckTitle":"Q&A","players":[],
         "playerLimit":50,"qa":{"featured":\(featured),"count":2,"questions":[\(questions)]}}
        """
        return try JSONDecoder().decode(LivePollSession.self, from: Data(json.utf8))
    }

    @Test func qaCardIsMarkedByItsPollId() {
        let card = ShowLivePoll(showId: UUID(), pollId: ShowLivePoll.qaPollId, title: "Q&A", questionCount: 1)
        #expect(card.isQA)
        let poll = ShowLivePoll(showId: UUID(), pollId: "poll-1", title: "Pulse", questionCount: 3)
        #expect(!poll.isQA)
    }

    @Test func decodesTheQuestionListAndFeaturedQuestion() throws {
        let session = try qaSession("""
            {"id":"a","text":"First?","from":"Sam","askedAt":1,"status":"featured"},
            {"id":"b","text":"Second?","from":null,"askedAt":2,"status":"new"}
            """, featured: #"{"id":"a","text":"First?","from":"Sam"}"#)
        #expect(session.mode == .qa)
        #expect(session.playerLimit == 50)
        #expect(session.qa?.featured?.text == "First?")
        #expect(session.qa?.questions?.map(\.status) == [.featured, .new])
    }

    @Test func cardShowsNewQuestionsUntilTheListIsOpened() throws {
        let store = QuestPollSessionStore.shared
        store.clear()
        defer { store.clear() }
        store.adopt(try qaSession("""
            {"id":"a","text":"First?","from":null,"askedAt":1,"status":"new"},
            {"id":"b","text":"Second?","from":null,"askedAt":2,"status":"new"}
            """))
        #expect(store.unseenQACount == 2)
        #expect(store.tileSubtitle == "QA1234 · 2 new")
        store.markQAQuestionsSeen()
        #expect(store.unseenQACount == 0)
        #expect(store.tileSubtitle == "QA1234")
    }

    @Test func questionListChangesUpdateTheCardNotTheRibbon() throws {
        let before = QuestPollSessionSnapshot(
            session: try qaSession(#"{"id":"a","text":"First?","from":null,"askedAt":1,"status":"new"}"#),
            membershipId: nil, questionCount: 1, practiceMembershipId: nil
        )
        let after = QuestPollSessionSnapshot(
            session: try qaSession(#"{"id":"a","text":"First?","from":null,"askedAt":1,"status":"featured"}"#),
            membershipId: nil, questionCount: 1, practiceMembershipId: nil
        )
        #expect(QuestPollSessionChange.classify(from: before, to: after) == .tile)
    }
}
