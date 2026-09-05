//
//  QuestPollClientTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct QuestPollClientTests {

    @Test func decodesPollList() throws {
        let data = Data("""
            {"polls":[{"id":"poll-1","title":"Session 1","questionCount":6}]}
            """.utf8)
        let list = try JSONDecoder().decode(QuestPollListResponse.self, from: data)
        #expect(list.polls == [
            QuestPollSummary(id: "poll-1", title: "Session 1", questionCount: 6)
        ])
    }

    @Test func decodesSessionEnvelope() throws {
        let data = Data("""
            {"session":{"id":"abc","code":"E2LG","pollId":"poll-1","pollTitle":"Session 1","mode":"live","status":"lobby","questionIndex":0,"voteCount":0,"isHost":true,"isController":true}}
            """.utf8)
        let envelope = try JSONDecoder().decode(
            QuestPollSessionEnvelope.self, from: data
        )
        let session = try #require(envelope.session)
        #expect(session.code == "E2LG")
        #expect(session.status == "lobby")
        #expect(session.isHost)
        #expect(session.question == nil)
        #expect(session.joinQrVisible == nil)
        #expect(!session.showsJoinQR)
    }

    @Test func decodesJoinQRVisible() throws {
        let data = Data("""
            {"session":{"id":"abc","code":"E2LG","pollId":"poll-1","pollTitle":"Session 1","mode":"live","status":"voting","questionIndex":0,"voteCount":0,"isHost":true,"isController":true,"joinQrVisible":true}}
            """.utf8)
        let envelope = try JSONDecoder().decode(
            QuestPollSessionEnvelope.self, from: data
        )
        let session = try #require(envelope.session)
        #expect(session.showsJoinQR)
    }

    @Test func decodesSessionWithQuestionPrompt() throws {
        let data = Data("""
            {"session":{"id":"abc","code":"E2LG","pollId":"poll-1","pollTitle":"Session 1","mode":"live","status":"question","questionIndex":0,"voteCount":3,"isHost":true,"isController":true,"question":{"id":"q1","text":"How long?","index":0,"totalQuestions":6}}}
            """.utf8)
        let envelope = try JSONDecoder().decode(
            QuestPollSessionEnvelope.self, from: data
        )
        let session = try #require(envelope.session)
        #expect(session.questionPrompt == "How long?")
        #expect(session.resolvedQuestionCount == 6)
        #expect(session.voteCount == 3)
    }

    @Test func decodesNullQuestion() throws {
        let data = Data("""
            {"session":{"id":"abc","code":"E2LG","pollId":"poll-1","pollTitle":"Session 1","mode":"live","status":"lobby","questionIndex":0,"voteCount":0,"isHost":true,"isController":true,"question":null}}
            """.utf8)
        let envelope = try JSONDecoder().decode(
            QuestPollSessionEnvelope.self, from: data
        )
        #expect(envelope.session?.question == nil)
    }

    @Test func presentURLMatchesProjectorPath() throws {
        let url = try #require(URL(string: "https://questpoll.live/present"))
        #expect(QuestPollConfig.isPresentURL(url))
        let nested = try #require(URL(string: "https://questpoll.live/present/"))
        #expect(QuestPollConfig.isPresentURL(nested))
        let withCode = try #require(
            URL(string: "https://questpoll.live/present?code=VR2V")
        )
        #expect(QuestPollConfig.isPresentURL(withCode))
        let other = try #require(URL(string: "https://example.com/present"))
        #expect(!QuestPollConfig.isPresentURL(other))
    }

    @Test func presentURLIncludesJoinCode() throws {
        let url = QuestPollConfig.presentURL(code: "VR2V")
        let items = queryItems(url)
        #expect(items.contains { $0.name == "code" && $0.value == "VR2V" })
        #expect(items.contains { $0.name == "aspect" })
        #expect(QuestPollConfig.isPresentURL(url))
        let page = QuestPollConfig.previewPage(code: "VR2V")
        #expect(page.url == url)
        #expect(page.id == QuestPollConfig.previewPageId)
    }

    @Test func presentURLsCarryDisplayModeAspect() {
        let previous = ExternalOutputSettings.orientation
        defer { ExternalOutputSettings.orientation = previous }

        ExternalOutputSettings.orientation = .landscape
        #expect(QuestPollConfig.presentAspectQueryItem.value == "16x9")
        #expect(aspect(of: QuestPollConfig.presentURL) == "16x9")
        let landscapeCode = QuestPollConfig.presentURL(code: "VR2V")
        #expect(aspect(of: landscapeCode) == "16x9")
        #expect(queryItems(landscapeCode).contains {
            $0.name == "code" && $0.value == "VR2V"
        })
        #expect(QuestPollConfig.isPresentURL(landscapeCode))
        let landscapePreview = QuestPollConfig.presentPreviewURL(pollId: "poll-1")
        #expect(aspect(of: landscapePreview) == "16x9")
        #expect(queryItems(landscapePreview).contains {
            $0.name == "pollId" && $0.value == "poll-1"
        })
        #expect(QuestPollConfig.previewPage(code: "VR2V").url == landscapeCode)
        #expect(QuestPollConfig.previewPage(pollId: "poll-1").url == landscapePreview)

        ExternalOutputSettings.orientation = .portrait
        #expect(QuestPollConfig.presentAspectQueryItem.value == "9x16")
        #expect(aspect(of: QuestPollConfig.presentURL) == "9x16")
        let verticalCode = QuestPollConfig.presentURL(code: "VR2V")
        #expect(aspect(of: verticalCode) == "9x16")
        #expect(queryItems(verticalCode).contains {
            $0.name == "code" && $0.value == "VR2V"
        })
        #expect(QuestPollConfig.isPresentURL(verticalCode))
        let verticalPreview = QuestPollConfig.presentPreviewURL(pollId: "poll-1")
        #expect(aspect(of: verticalPreview) == "9x16")
        #expect(queryItems(verticalPreview).contains {
            $0.name == "pollId" && $0.value == "poll-1"
        })
        #expect(queryItems(verticalPreview).contains {
            $0.name == "preview" && $0.value == "1"
        })
        #expect(QuestPollConfig.previewPage(code: "VR2V").url == verticalCode)
        #expect(QuestPollConfig.previewPage(pollId: "poll-1").url == verticalPreview)
    }

    @Test func accountLinkRoundTripMigratesKeychain() {
        let suite = "QuestPollAccountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var keychain: [String: String] = [:]
        let account = QuestPollAccount(
            defaults: defaults,
            keychainGet: { keychain[$0] },
            keychainSet: { value, key in keychain[key] = value },
            keychainRemove: { keychain.removeValue(forKey: $0) }
        )
        #expect(!account.isLinked)
        account.link(pin: "4242")
        #expect(account.isLinked)
        #expect(account.hostPIN == "4242")
        #expect(keychain["Eclipse.questpoll.hostPin"] == "4242")
        #expect(defaults.string(forKey: "Eclipse.questpoll.hostPin") == nil)
        let hostId = account.hostId
        #expect(!hostId.isEmpty)
        #expect(account.hostId == hostId)
        account.unlink()
        #expect(!account.isLinked)
        #expect(keychain["Eclipse.questpoll.hostPin"] == nil)
        #expect(account.hostId == hostId)
    }

    @Test func accountMigratesLegacyUserDefaultsPIN() {
        let suite = "QuestPollAccountMigrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("9999", forKey: "Eclipse.questpoll.hostPin")
        var keychain: [String: String] = [:]
        let account = QuestPollAccount(
            defaults: defaults,
            keychainGet: { keychain[$0] },
            keychainSet: { value, key in keychain[key] = value },
            keychainRemove: { keychain.removeValue(forKey: $0) }
        )
        #expect(account.hostPIN == "9999")
        #expect(keychain["Eclipse.questpoll.hostPin"] == "9999")
        #expect(defaults.string(forKey: "Eclipse.questpoll.hostPin") == nil)
    }

    @Test func previewPageUsesPresentURL() {
        #expect(QuestPollConfig.previewPage.url == QuestPollConfig.presentURL)
        #expect(QuestPollConfig.previewPage.id == QuestPollConfig.previewPageId)
        #expect(QuestPollConfig.previewPage.title == "Live Poll")
    }

    @Test func practicePreviewURLUsesPollIdWithoutCode() {
        let url = QuestPollConfig.presentPreviewURL(pollId: "poll-1")
        #expect(QuestPollConfig.isPresentURL(url))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        #expect(items.contains { $0.name == "pollId" && $0.value == "poll-1" })
        #expect(items.contains { $0.name == "preview" && $0.value == "1" })
        #expect(items.contains { $0.name == "aspect" })
        #expect(!items.contains { $0.name == "code" })
        let page = QuestPollConfig.previewPage(pollId: "poll-1")
        #expect(page.url == url)
        #expect(page.id != QuestPollConfig.previewPageId)
        let again = QuestPollConfig.previewPage(pollId: "poll-1")
        #expect(again.id == page.id)
    }

    @Test func hostURLPointsAtHostConsole() {
        #expect(QuestPollConfig.hostURL.absoluteString.hasSuffix("/host"))
    }

    private func queryItems(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func aspect(of url: URL) -> String? {
        queryItems(url).first { $0.name == "aspect" }?.value
    }
}
