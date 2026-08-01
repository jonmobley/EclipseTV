//
//  WebPageStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Covers the salvage path added in the audit. A single malformed entry used to take
//  every saved page with it: load() reset `pages` to empty, and the next write then
//  persisted that empty array over the user's bookmarks permanently.
//
//  The invariant worth pinning is that load() never writes to the items key. It may
//  only copy unreadable bytes to the backup key, so a decode bug stays recoverable
//  instead of becoming data loss.
//

import Testing
import Foundation
@testable import EclipseiPhone

@MainActor
struct WebPageStoreTests {

    private let itemsKey = "EclipseTV.pages.items"
    private let backupKey = "EclipseTV.pages.items.unreadableBackup"

    /// A throwaway suite per test, so cases can't leak into each other or into the app.
    private func makeDefaults() throws -> UserDefaults {
        let suite = "WebPageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func page(_ title: String, _ host: String) throws -> WebPage {
        WebPage(title: title, url: try #require(URL(string: "https://\(host)")))
    }

    /// One entry that still decodes, one that can't. `[WebPage]` fails on the second,
    /// which is what sends load() down the salvage path.
    private func partiallyCorruptPayload() -> Data {
        let json = """
        [
          {
            "id": "\(UUID().uuidString)",
            "title": "Survivor",
            "url": "https://survivor.example",
            "createdAt": 0
          },
          { "title": "missing id, url, and createdAt" }
        ]
        """
        return Data(json.utf8)
    }

    @Test func loadsWellFormedPagesInOrder() throws {
        let defaults = try makeDefaults()
        let saved = [try page("One", "one.example"), try page("Two", "two.example")]
        defaults.set(try JSONEncoder().encode(saved), forKey: itemsKey)

        let store = WebPageStore(defaults: defaults)

        #expect(store.pages.map(\.title) == ["One", "Two"])
        #expect(store.didFailToLoad == false)
        #expect(defaults.data(forKey: backupKey) == nil)
    }

    @Test func missingPayloadIsNotAFailure() throws {
        let defaults = try makeDefaults()

        let store = WebPageStore(defaults: defaults)

        #expect(store.pages.isEmpty)
        #expect(store.didFailToLoad == false)
        #expect(defaults.data(forKey: backupKey) == nil)
    }

    @Test func salvagesReadableEntriesAndKeepsTheOriginalBytes() throws {
        let defaults = try makeDefaults()
        let raw = partiallyCorruptPayload()
        defaults.set(raw, forKey: itemsKey)

        let store = WebPageStore(defaults: defaults)

        // The readable entry survives rather than being dropped along with the bad one.
        #expect(store.pages.map(\.title) == ["Survivor"])
        // A partial recovery still backs up the bytes, so the lost entry is diagnosable.
        #expect(defaults.data(forKey: backupKey) == raw)
        #expect(defaults.data(forKey: itemsKey) == raw)
        // Salvage is a recovery, not a hard failure: the list is usable as-is.
        #expect(store.didFailToLoad == false)
    }

    @Test func unreadablePayloadIsPreservedNotOverwritten() throws {
        let defaults = try makeDefaults()
        let raw = Data("this is not JSON at all".utf8)
        defaults.set(raw, forKey: itemsKey)

        let store = WebPageStore(defaults: defaults)

        #expect(store.pages.isEmpty)
        #expect(store.didFailToLoad)
        #expect(defaults.data(forKey: backupKey) == raw)
        // The actual regression: load() must leave the items key exactly as it found it.
        #expect(defaults.data(forKey: itemsKey) == raw)
    }

    @Test func salvagedPagesCanStillBeReEncoded() throws {
        let defaults = try makeDefaults()
        defaults.set(partiallyCorruptPayload(), forKey: itemsKey)

        let store = WebPageStore(defaults: defaults)
        let round = try JSONDecoder().decode(
            [WebPage].self, from: try JSONEncoder().encode(store.pages)
        )

        #expect(round == store.pages)
    }

    @Test func blankTitleDefaultsToURLHost() throws {
        let defaults = try makeDefaults()
        let store = WebPageStore(defaults: defaults)

        let page = try store.add(title: "  ", urlString: "example.com/path")

        #expect(page.title == "example.com")
        #expect(page.url.absoluteString == "https://example.com/path")
    }
}
