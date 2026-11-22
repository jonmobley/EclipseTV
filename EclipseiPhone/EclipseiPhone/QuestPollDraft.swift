//
//  QuestPollDraft.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit

/// A poll being written or changed in the app, before it is saved to QuestPoll.
///
/// Looser than `LivePollDeck` on purpose: answers may be blank while typing and
/// a quiz may not have its right answer marked yet. `problem` says what still
/// stops a save, and `deck()` produces the cleaned-up version the server takes.
/// The limits mirror the server's (`quest-relay/src/limits.ts`).
struct QuestPollDraft: Equatable {

    static let maxQuestions = 60
    static let maxTitleCharacters = 80
    static let maxPromptCharacters = 240
    static let maxOptionCharacters = 120
    static let minOptions = 2
    static let maxOptions = 5
    static let minSeconds = 5
    static let maxSeconds = 300
    static let defaultSeconds = 30

    /// Answer windows offered in the Time menus.
    static let timeChoices = [10, 15, 20, 30, 45, 60, 90, 120, 180, 300]

    struct Question: Equatable {
        var prompt: String
        /// Answer texts in order; blank ones are dropped on save.
        var options: [String]
        /// Row of the right answer (quiz only). Kept while the poll is a Poll
        /// so switching back to Quiz does not lose it.
        var correctIndex: Int?
        var seconds: Int

        /// Answers that have text, in order.
        var filledOptions: [String] {
            options
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        /// `correctIndex` counted among the answers that have text, or nil
        /// when none is marked or the marked answer is blank.
        var filledCorrectIndex: Int? {
            guard let correctIndex, options.indices.contains(correctIndex),
                  !options[correctIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return options[..<correctIndex]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .count
        }
    }

    /// QuestPoll's id; nil until the poll is first saved.
    var id: String?
    var title: String
    /// `.poll` or `.quiz`.
    var mode: LivePollMode
    var showQuestionOnPhone: Bool
    var questions: [Question]

    // MARK: - Init

    /// A new poll: one empty question, question shown on phones (the
    /// website's default for polls made there).
    init() {
        id = nil
        title = ""
        mode = .poll
        showQuestionOnPhone = true
        questions = [Self.blankQuestion(seconds: Self.defaultSeconds)]
    }

    init(deck: LivePollDeck) {
        id = deck.id
        title = deck.title
        mode = deck.mode == .quiz ? .quiz : .poll
        showQuestionOnPhone = deck.showQuestionOnPhone
        questions = deck.questions.map { question in
            Question(
                prompt: question.prompt,
                options: question.options.map(\.text),
                correctIndex: question.correctIndex,
                seconds: Self.clampedSeconds(question.timeLimitSeconds)
            )
        }
    }

    static func blankQuestion(seconds: Int) -> Question {
        Question(prompt: "", options: ["", ""], correctIndex: nil, seconds: seconds)
    }

    // MARK: - Timers

    /// The answer window most questions use; new questions start with it.
    var commonSeconds: Int {
        var counts: [Int: Int] = [:]
        var best = Self.defaultSeconds
        var bestCount = 0
        for question in questions {
            let count = (counts[question.seconds] ?? 0) + 1
            counts[question.seconds] = count
            if count > bestCount {
                bestCount = count
                best = question.seconds
            }
        }
        return best
    }

    /// True when questions do not all share one answer window.
    var hasMixedTimers: Bool {
        Set(questions.map(\.seconds)).count > 1
    }

    mutating func setAllSeconds(_ seconds: Int) {
        let value = Self.clampedSeconds(seconds)
        for index in questions.indices {
            questions[index].seconds = value
        }
    }

    static func clampedSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minSeconds), maxSeconds)
    }

    /// "30 seconds", "1 minute", "1 min 30 sec".
    static func timeLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = seconds / 60
        let rest = seconds % 60
        if rest == 0 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        return "\(minutes) min \(rest) sec"
    }

    /// `timeChoices`, plus `current` when it is not one of them (a poll made
    /// on the website can use any whole number of seconds).
    static func timeChoices(including current: Int) -> [Int] {
        timeChoices.contains(current) ? timeChoices : (timeChoices + [current]).sorted()
    }

    // MARK: - Saving

    var canAddQuestion: Bool { questions.count < Self.maxQuestions }

    /// What still stops a save, in words for the person; nil when ready.
    var problem: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give this \(noun) a name."
        }
        if questions.isEmpty { return "Add at least one question." }
        for (index, question) in questions.enumerated() {
            let name = "Question \(index + 1)"
            if question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(name) has no question text."
            }
            if question.filledOptions.count < Self.minOptions {
                return "\(name) needs at least two answers."
            }
            if mode == .quiz, question.filledCorrectIndex == nil {
                return "\(name) needs its right answer marked."
            }
        }
        return nil
    }

    /// "poll" or "quiz", for sentences.
    var noun: String { mode == .quiz ? "quiz" : "poll" }

    /// The poll as the server stores it: text trimmed and cut to the limits,
    /// blank answers dropped, ids numbered by position (as the website does,
    /// so reordering or deleting can never leave two questions sharing an id).
    func deck() -> LivePollDeck {
        let cleaned = questions.enumerated().map { index, question -> LivePollQuestion in
            let number = index + 1
            let options = question.filledOptions.enumerated().map { optionIndex, text in
                LivePollOption(
                    id: "q\(number)-o\(optionIndex + 1)",
                    text: String(text.prefix(Self.maxOptionCharacters))
                )
            }
            let prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return LivePollQuestion(
                id: "q\(number)",
                prompt: String(prompt.prefix(Self.maxPromptCharacters)),
                options: options,
                correctIndex: mode == .quiz ? question.filledCorrectIndex : nil,
                timeLimitSeconds: Self.clampedSeconds(question.seconds)
            )
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return LivePollDeck(
            id: id,
            title: String(trimmedTitle.prefix(Self.maxTitleCharacters)),
            questions: cleaned,
            showQuestionOnPhone: showQuestionOnPhone,
            mode: mode
        )
    }
}
