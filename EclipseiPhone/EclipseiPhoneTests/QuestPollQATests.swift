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

    private func session(json: String) throws -> LivePollSession {
        try JSONDecoder().decode(LivePollSession.self, from: Data(json.utf8))
    }

    @Test func tapRepliesWithoutTheListKeepTheQuestions() throws {
        let store = QuestPollSessionStore.shared
        store.clear()
        defer { store.clear() }
        store.adopt(try qaSession("""
            {"id":"a","text":"First?","from":null,"askedAt":1,"status":"new"},
            {"id":"b","text":"Second?","from":null,"askedAt":2,"status":"new"}
            """))
        // A command reply: featured question and count, no list.
        store.adopt(try session(json: """
            {"phase":"lobby","joinCode":"QA1234","mode":"qa","deckTitle":"Q&A","players":[],
             "qa":{"featured":{"id":"a","text":"First?","from":null},"count":2}}
            """))
        #expect(store.session?.qa?.featured?.id == "a")
        #expect(store.session?.qa?.questions?.map(\.id) == ["a", "b"])
    }

    @Test func aDifferentRoomDoesNotInheritTheList() throws {
        let current = try qaSession(#"{"id":"a","text":"First?","from":null,"askedAt":1,"status":"new"}"#)
        let other = try session(json: """
            {"phase":"lobby","joinCode":"OTHER1","mode":"qa","deckTitle":"Q&A","players":[],
             "qa":{"featured":null,"count":0}}
            """)
        let merged = QuestPollSessionStore.keepingQAQuestions(of: current, in: other)
        #expect(merged.qa?.questions == nil)
    }

    @Test func listsAreNewestFirstAndAStrayFeaturedQuestionIsShown() throws {
        let questions = try qaSession("""
            {"id":"old","text":"Old?","from":null,"askedAt":1,"status":"new"},
            {"id":"newer","text":"Newer?","from":null,"askedAt":5,"status":"new"},
            {"id":"stray","text":"Stray?","from":null,"askedAt":3,"status":"featured"},
            {"id":"live","text":"Live?","from":null,"askedAt":4,"status":"featured"},
            {"id":"h","text":"Hidden?","from":null,"askedAt":2,"status":"hidden"}
            """).qa?.questions ?? []
        let sections = QuestPollQAViewController.sections(questions: questions, featuredId: "live")
        #expect(sections.new.map(\.id) == ["newer", "old"])
        #expect(sections.shown.map(\.id) == ["stray"])
        #expect(sections.hidden.map(\.id) == ["h"])
    }

    @Test func refreshNoticesARoomEndedElsewhere() throws {
        let ended = try session(json: """
            {"phase":"ended","joinCode":"QA1234","mode":"qa","deckTitle":"Q&A","players":[]}
            """)
        #expect(QuestPollStatusPoll.roomIsGone(.success(ended)))
        #expect(QuestPollStatusPoll.roomIsGone(.failure(LivePollError.server("Session not found"))))
        #expect(!QuestPollStatusPoll.roomIsGone(.failure(LivePollError.transport)))
        #expect(!QuestPollStatusPoll.roomIsGone(.success(try qaSession(""))))
    }
}
