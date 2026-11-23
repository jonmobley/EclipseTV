//
//  QuestPollDraftTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit
import Testing
@testable import EclipseiPhone

struct QuestPollDraftTests {

    private func question(
        _ prompt: String = "Where to?",
        _ options: [String] = ["Beach", "Hills"],
        correct: Int? = nil,
        seconds: Int = 30
    ) -> QuestPollDraft.Question {
        QuestPollDraft.Question(
            prompt: prompt, options: options, correctIndex: correct, seconds: seconds
        )
    }

    private func draft(
        title: String = "Trip", mode: LivePollMode = .poll,
        _ questions: [QuestPollDraft.Question]
    ) -> QuestPollDraft {
        var draft = QuestPollDraft()
        draft.title = title
        draft.mode = mode
        draft.questions = questions
        return draft
    }

    // MARK: - New poll

    @Test func newPollStartsWithOneEmptyQuestionAndCannotBeSaved() {
        let blank = QuestPollDraft()
        #expect(blank.id == nil)
        #expect(blank.mode == .poll)
        #expect(blank.showQuestionOnPhone)
        #expect(blank.questions.count == 1)
        #expect(blank.questions[0].options == ["", ""])
        #expect(blank.problem == "Give this poll a name.")
    }

    // MARK: - What stops a save

    @Test func problemNamesTheFirstThingMissing() {
        #expect(draft([question()]).problem == nil)
        #expect(draft(title: "  ", [question()]).problem == "Give this poll a name.")
        #expect(draft(title: " ", mode: .quiz, [question()]).problem == "Give this quiz a name.")
        #expect(draft([]).problem == "Add at least one question.")
        #expect(
            draft([question(), question("  ")]).problem == "Question 2 has no question text."
        )
        #expect(
            draft([question("Q", ["Only one", "  "])]).problem
                == "Question 1 needs at least two answers."
        )
    }

    @Test func quizNeedsARightAnswerThatHasText() {
        #expect(
            draft(mode: .quiz, [question()]).problem == "Question 1 needs its right answer marked."
        )
        #expect(draft(mode: .quiz, [question(correct: 1)]).problem == nil)
        // The marked answer was left blank: that is not a right answer.
        #expect(
            draft(mode: .quiz, [question("Q", ["A", "B", ""], correct: 2)]).problem
                == "Question 1 needs its right answer marked."
        )
        // A plain poll never needs one.
        #expect(draft(mode: .poll, [question()]).problem == nil)
    }

    // MARK: - What is sent

    @Test func deckTrimsDropsBlankAnswersAndNumbersIdsByPosition() {
        let deck = draft(title: "  Trip  ", [
            question("  First?  ", [" A ", "", "B"]),
            question("Second?", ["C", "D"])
        ]).deck()
        #expect(deck.title == "Trip")
        #expect(deck.mode == .poll)
        #expect(deck.questions.map(\.id) == ["q1", "q2"])
        #expect(deck.questions[0].prompt == "First?")
        #expect(deck.questions[0].options.map(\.text) == ["A", "B"])
        #expect(deck.questions[0].options.map(\.id) == ["q1-o1", "q1-o2"])
        #expect(deck.questions[1].options.map(\.id) == ["q2-o1", "q2-o2"])
    }

    @Test func rightAnswerFollowsItsAnswerWhenBlanksAreDropped() {
        let quiz = draft(mode: .quiz, [question("Q", ["", "Wrong", "Right"], correct: 2)]).deck()
        #expect(quiz.questions[0].options.map(\.text) == ["Wrong", "Right"])
        #expect(quiz.questions[0].correctIndex == 1)
        // The same questions saved as a poll carry no right answer.
        let poll = draft(mode: .poll, [question("Q", ["A", "B"], correct: 1)]).deck()
        #expect(poll.questions[0].correctIndex == nil)
    }

    @Test func deckCutsTextToTheServerLimits() {
        let long = String(repeating: "x", count: 400)
        let deck = draft(title: long, [question(long, [long, long])]).deck()
        #expect(deck.title.count == QuestPollDraft.maxTitleCharacters)
        #expect(deck.questions[0].prompt.count == QuestPollDraft.maxPromptCharacters)
        #expect(deck.questions[0].options[0].text.count == QuestPollDraft.maxOptionCharacters)
    }

    @Test func loadingASavedPollAndSavingItUnchangedKeepsItsContent() {
        let saved = LivePollDeck(
            id: "abc",
            title: "Quiz night",
            questions: [LivePollQuestion(
                id: "q1", prompt: "2 + 2?",
                options: [
                    LivePollOption(id: "q1-o1", text: "3"),
                    LivePollOption(id: "q1-o2", text: "4")
                ],
                correctIndex: 1, timeLimitSeconds: 45
            )],
            showQuestionOnPhone: false,
            mode: .quiz
        )
        let draft = QuestPollDraft(deck: saved)
        #expect(draft.problem == nil)
        #expect(draft.deck() == saved)
    }

    // MARK: - Timers

    @Test func timePerQuestionIsTheMostCommonOne() {
        var mixed = draft([
            question(seconds: 20), question(seconds: 60), question(seconds: 60)
        ])
        #expect(mixed.commonSeconds == 60)
        #expect(mixed.hasMixedTimers)
        mixed.setAllSeconds(15)
        #expect(!mixed.hasMixedTimers)
        #expect(mixed.questions.map(\.seconds) == [15, 15, 15])
        mixed.setAllSeconds(9_999)
        #expect(mixed.commonSeconds == QuestPollDraft.maxSeconds)
    }

    @Test func timeLabelsAndChoices() {
        #expect(QuestPollDraft.timeLabel(30) == "30 seconds")
        #expect(QuestPollDraft.timeLabel(60) == "1 minute")
        #expect(QuestPollDraft.timeLabel(120) == "2 minutes")
        #expect(QuestPollDraft.timeLabel(90) == "1 min 30 sec")
        #expect(QuestPollDraft.timeChoices(including: 30) == QuestPollDraft.timeChoices)
        // A length set on the website stays selectable.
        #expect(QuestPollDraft.timeChoices(including: 25).contains(25))
    }

    @Test func questionCountIsCapped() {
        var full = draft(Array(repeating: question(), count: QuestPollDraft.maxQuestions))
        #expect(!full.canAddQuestion)
        full.questions.removeLast()
        #expect(full.canAddQuestion)
    }

    // MARK: - Answer list edits

    @Test func rightAnswerMarkMovesWithItsAnswer() {
        let start = question("Q", ["A", "B", "C"], correct: 0)
        let moved = QuestPollQuestionEditorViewController.movingAnswer(in: start, from: 0, to: 2)
        #expect(moved.options == ["B", "C", "A"])
        #expect(moved.correctIndex == 2)
        let other = QuestPollQuestionEditorViewController.movingAnswer(in: start, from: 2, to: 0)
        #expect(other.options == ["C", "A", "B"])
        #expect(other.correctIndex == 1)
    }

    @Test func removingAnAnswerKeepsOrClearsTheMark() {
        let start = question("Q", ["A", "B", "C"], correct: 2)
        let kept = QuestPollQuestionEditorViewController.removingAnswer(in: start, at: 0)
        #expect(kept.options == ["B", "C"])
        #expect(kept.correctIndex == 1)
        let cleared = QuestPollQuestionEditorViewController.removingAnswer(in: start, at: 2)
        #expect(cleared.options == ["A", "B"])
        #expect(cleared.correctIndex == nil)
    }

    // MARK: - Typing limits

    @Test func typingStopsAtTheLimitButDeletingAlwaysWorks() {
        let full = String(repeating: "a", count: 10)
        let end = NSRange(location: 10, length: 0)
        #expect(!QuestPollEditorText.allows(current: full, range: end, replacement: "b", limit: 10))
        #expect(QuestPollEditorText.allows(
            current: full, range: NSRange(location: 9, length: 1), replacement: "", limit: 10
        ))
        #expect(QuestPollEditorText.allows(
            current: full, range: NSRange(location: 0, length: 1), replacement: "b", limit: 10
        ))
        #expect(QuestPollEditorText.allows(current: "abc", range: NSRange(location: 3, length: 0), replacement: "d", limit: 10))
    }
}
