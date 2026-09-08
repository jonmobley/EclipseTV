//
//  QuestPollClientTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit
import Testing
@testable import EclipseiPhone

struct QuestPollClientTests {

    @Test func presentURLMatchesProjectorPath() throws {
        let url = try #require(URL(string: "https://quest.eclipseapp.com/present"))
        #expect(QuestPollConfig.isPresentURL(url))
        let nested = try #require(URL(string: "https://quest.eclipseapp.com/present/"))
        #expect(QuestPollConfig.isPresentURL(nested))
        let withCode = try #require(
            URL(string: "https://quest.eclipseapp.com/present?code=VR2V")
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

    @Test @MainActor func presentURLsCarryDisplayModeAspect() {
        ExternalOutputOrientationFixture.withSwitching { set in
            set(.landscape)
            expectPresentURLs(aspect: "16x9")
            set(.portrait)
            expectPresentURLs(aspect: "9x16")
        }
    }

    private func expectPresentURLs(aspect expected: String) {
        #expect(QuestPollConfig.presentAspectQueryItem.value == expected)
        #expect(aspect(of: QuestPollConfig.presentURL) == expected)
        let code = QuestPollConfig.presentURL(code: "VR2V")
        #expect(aspect(of: code) == expected)
        #expect(queryItems(code).contains { $0.name == "code" && $0.value == "VR2V" })
        #expect(QuestPollConfig.isPresentURL(code))
        let preview = QuestPollConfig.presentPreviewURL(pollId: "poll-1")
        #expect(aspect(of: preview) == expected)
        #expect(queryItems(preview).contains {
            $0.name == "pollId" && $0.value == "poll-1"
        })
        #expect(queryItems(preview).contains { $0.name == "preview" && $0.value == "1" })
        #expect(QuestPollConfig.previewPage(code: "VR2V").url == code)
        #expect(QuestPollConfig.previewPage(pollId: "poll-1").url == preview)
    }

    @Test func accountTokenRoundTrip() {
        var keychain: [String: String] = [:]
        let account = LivePollAccount(
            keychainGet: { keychain[$0] },
            keychainSet: { value, key in keychain[key] = value },
            keychainRemove: { keychain.removeValue(forKey: $0) }
        )
        #expect(!account.isSignedIn)
        account.signIn(token: "tok-abc")
        #expect(account.isSignedIn)
        #expect(account.accountToken == "tok-abc")
        #expect(keychain["Eclipse.livepoll.accountToken"] == "tok-abc")
        account.signOut()
        #expect(!account.isSignedIn)
        #expect(keychain["Eclipse.livepoll.accountToken"] == nil)
    }

    @Test func prepareEmailSignInClearsLegacyPIN() {
        let pinKey = "Eclipse.questpoll.hostPin"
        let promptedKey = "Eclipse.livepoll.didPromptPINMigration"
        KeychainStore.set("4242", forKey: pinKey)
        UserDefaults.standard.removeObject(forKey: promptedKey)
        defer {
            KeychainStore.removeValue(forKey: pinKey)
            UserDefaults.standard.removeObject(forKey: promptedKey)
        }
        _ = LivePollAccountStore.prepareEmailSignInPrompt()
        #expect(KeychainStore.string(forKey: pinKey) == nil)
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
        #expect(QuestPollConfig.origin.host == "quest.eclipseapp.com")
    }

    @Test func joinURLUsesUnifiedOrigin() {
        let url = QuestPollConfig.joinURL(code: "VR2V")
        #expect(url.host == "quest.eclipseapp.com")
        #expect(url.path.hasSuffix("/join/VR2V"))
    }

    private func queryItems(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func aspect(of url: URL) -> String? {
        queryItems(url).first { $0.name == "aspect" }?.value
    }
}
