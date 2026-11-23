//
//  QuestPollEditorTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit
import Testing
import UIKit
@testable import EclipseiPhone

/// Saving polls from the app: the calls sent to QuestPoll, and the editor screen.
@MainActor
@Suite(.serialized)
struct QuestPollEditorTests {

    private let deck = LivePollDeck(
        title: "Trip",
        questions: [LivePollQuestion(
            id: "q1", prompt: "Where to?",
            options: [
                LivePollOption(id: "q1-o1", text: "Beach"),
                LivePollOption(id: "q1-o2", text: "Hills")
            ],
            timeLimitSeconds: 30
        )],
        showQuestionOnPhone: true,
        mode: .poll
    )

    private func client() -> LivePollClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingPollProtocol.self]
        return LivePollClient(
            origin: URL(string: "https://example.invalid")!,
            session: URLSession(configuration: config),
            accountToken: "token-123"
        )
    }

    private func stored(id: String) throws -> Data {
        var saved = deck
        saved.id = id
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
        return try JSONSerialization.data(withJSONObject: ["poll": object])
    }

    // MARK: - Calls

    @Test func newPollIsPostedAndComesBackWithItsId() async throws {
        RecordingPollProtocol.reset(status: 200, body: try stored(id: "new-1"))
        let saved = try await QuestPollDeckWriter(client: client()).save(deck)
        #expect(saved.id == "new-1")
        let request = try #require(RecordingPollProtocol.requests.last)
        #expect(request.method == "POST")
        #expect(request.path == "/api/polls")
        #expect(request.authorization == "Bearer token-123")
        let sent = try JSONDecoder().decode(LivePollDeck.self, from: request.body)
        #expect(sent.title == "Trip")
        #expect(sent.questions.first?.options.map(\.text) == ["Beach", "Hills"])
    }

    @Test func savedPollIsReplacedInPlace() async throws {
        RecordingPollProtocol.reset(status: 200, body: try stored(id: "abc"))
        var existing = deck
        existing.id = "abc"
        _ = try await QuestPollDeckWriter(client: client()).save(existing)
        let request = try #require(RecordingPollProtocol.requests.last)
        #expect(request.method == "PUT")
        #expect(request.path == "/api/polls/abc")
    }

    @Test func deleteCallsThePollsAddress() async throws {
        RecordingPollProtocol.reset(status: 200, body: Data(#"{"ok":true}"#.utf8))
        try await QuestPollDeckWriter(client: client()).delete(pollId: "abc")
        let request = try #require(RecordingPollProtocol.requests.last)
        #expect(request.method == "DELETE")
        #expect(request.path == "/api/polls/abc")
    }

    @Test func serverRefusalsBecomeReadableErrors() async throws {
        RecordingPollProtocol.reset(
            status: 400, body: Data(#"{"error":"deck title is required"}"#.utf8)
        )
        await #expect(throws: LivePollError.server("deck title is required")) {
            _ = try await QuestPollDeckWriter(client: self.client()).save(self.deck)
        }
        RecordingPollProtocol.reset(status: 401, body: Data("{}".utf8))
        await #expect(throws: LivePollError.unauthorized) {
            _ = try await QuestPollDeckWriter(client: self.client()).save(self.deck)
        }
    }

    // MARK: - Screen

    @Test func newPollScreenStartsUnsavableWithItsSections() {
        let editor = QuestPollEditorViewController(target: .new, client: client())
        editor.loadViewIfNeeded()
        #expect(editor.title == "New Poll")
        // Details and Questions; Delete appears only for a saved poll.
        #expect(editor.tableView.numberOfSections == 2)
        #expect(editor.tableView.numberOfRows(inSection: 0) == 4)
        // One empty question plus the Add Question row.
        #expect(editor.tableView.numberOfRows(inSection: 1) == 2)
        #expect(editor.navigationItem.rightBarButtonItem?.isEnabled == false)
        #expect(!editor.isDirty)
        #expect(editor.statusText == "Give this poll a name.")
    }

    @Test func questionRowsSayWhatIsInThem() {
        let empty = QuestPollDraft.blankQuestion(seconds: 30)
        #expect(QuestPollEditorViewController.questionTitle(empty, number: 3) == "3. New question")
        #expect(
            QuestPollEditorViewController.questionDetail(empty, showsTime: false)
                == "No answers yet"
        )
        let filled = QuestPollDraft.Question(
            prompt: "Where to?", options: ["Beach", "Hills", ""], correctIndex: nil, seconds: 90
        )
        #expect(QuestPollEditorViewController.questionTitle(filled, number: 1) == "1. Where to?")
        #expect(
            QuestPollEditorViewController.questionDetail(filled, showsTime: true)
                == "2 answers · 1 min 30 sec"
        )
    }

    @Test func deleteWarningCountsTheShowCardsThatUseThePoll() {
        let none = QuestPollEditorViewController.deleteMessage(title: "Trip", cardsUsingIt: 0)
        #expect(none.hasPrefix("“Trip” is removed"))
        #expect(!none.contains("card"))
        let one = QuestPollEditorViewController.deleteMessage(title: "Trip", cardsUsingIt: 1)
        #expect(one.contains("1 card in your Shows uses it"))
        let two = QuestPollEditorViewController.deleteMessage(title: " ", cardsUsingIt: 2)
        #expect(two.hasPrefix("This poll is removed"))
        #expect(two.contains("2 cards in your Shows use it"))
    }

    @Test func questionScreenOffersTwoToFiveAnswers() {
        let editor = QuestPollQuestionEditorViewController(
            question: QuestPollDraft.Question(
                prompt: "Q", options: ["A"], correctIndex: nil, seconds: 30
            ),
            number: 2, isQuiz: true, canDelete: true
        )
        editor.loadViewIfNeeded()
        #expect(editor.title == "Question 2")
        // Padded to two answer rows, plus Add Answer.
        #expect(editor.question.options == ["A", ""])
        #expect(editor.tableView.numberOfRows(inSection: 1) == 3)
        #expect(editor.tableView.numberOfSections == 4)

        let full = QuestPollQuestionEditorViewController(
            question: QuestPollDraft.Question(
                prompt: "Q", options: ["A", "B", "C", "D", "E"], correctIndex: nil, seconds: 30
            ),
            number: 1, isQuiz: false, canDelete: false
        )
        full.loadViewIfNeeded()
        // Five answers is the most: no Add Answer row, and no Delete Question.
        #expect(full.tableView.numberOfRows(inSection: 1) == 5)
        #expect(full.tableView.numberOfSections == 3)
    }
}

/// Answers every request with a canned reply and remembers what was asked.
private final class RecordingPollProtocol: URLProtocol, @unchecked Sendable {

    struct Recorded {
        let method: String
        let path: String
        let authorization: String?
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var reply = Data()
    nonisolated(unsafe) private static var recorded: [Recorded] = []

    static var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func reset(status: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.status = status
        reply = body
        recorded = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://example.invalid")!
        Self.lock.lock()
        Self.recorded.append(Recorded(
            method: request.httpMethod ?? "",
            path: url.path,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: Self.bodyData(of: request)
        ))
        let status = Self.status
        let reply = Self.reply
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands a protocol the body as a stream, not as `httpBody`.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
