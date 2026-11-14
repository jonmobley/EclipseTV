//
//  WebHistoryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Recent pages behind the browser's history drawer, and the drawer itself.
@MainActor
struct WebHistoryTests {

    private func makeStore() throws -> (WebHistoryStore, UserDefaults) {
        let suite = "WebHistory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (WebHistoryStore(defaults: defaults), defaults)
    }

    private let apple = URL(string: "https://www.apple.com/")!
    private let wiki = URL(string: "https://en.wikipedia.org/wiki/Eclipse")!

    @Test func newestPageComesFirstAndARevisitMovesUp() throws {
        let (store, _) = try makeStore()
        store.record(url: apple, title: "Apple", at: Date(timeIntervalSince1970: 1))
        store.record(url: wiki, title: "Eclipse", at: Date(timeIntervalSince1970: 2))
        #expect(store.entries.map(\.url) == [wiki, apple])

        store.record(url: apple, title: "Apple (New)", at: Date(timeIntervalSince1970: 3))
        #expect(store.entries.map(\.url) == [apple, wiki])
        #expect(store.entries.first?.title == "Apple (New)")
    }

    @Test func aFragmentIsTheSamePage() throws {
        let (store, _) = try makeStore()
        store.record(url: wiki, title: "Eclipse")
        store.record(url: URL(string: "https://en.wikipedia.org/wiki/Eclipse#Types")!, title: "Eclipse")
        #expect(store.entries.count == 1)
    }

    @Test func untitledPagesUseTheHostAndOnlyWebAddressesCount() throws {
        let (store, _) = try makeStore()
        store.record(url: apple, title: "  ")
        store.record(url: URL(string: "about:blank")!, title: "Blank")
        store.record(url: URL(fileURLWithPath: "/tmp/page.html"), title: "File")
        #expect(store.entries.map(\.title) == ["apple.com"])
    }

    @Test func keepsOnlyTheNewestPages() throws {
        let (store, _) = try makeStore()
        for index in 0..<(WebHistoryStore.limit + 5) {
            store.record(url: URL(string: "https://example.com/\(index)")!, title: "\(index)")
        }
        #expect(store.entries.count == WebHistoryStore.limit)
        #expect(store.entries.first?.title == "\(WebHistoryStore.limit + 4)")
    }

    @Test func pagesSurviveARelaunchAndClearEmptiesThem() throws {
        let (store, defaults) = try makeStore()
        store.record(url: apple, title: "Apple")
        #expect(WebHistoryStore(defaults: defaults).entries.map(\.url) == [apple])

        store.clear()
        #expect(store.entries.isEmpty)
        #expect(WebHistoryStore(defaults: defaults).entries.isEmpty)
    }

    @Test func drawerListsSavedThenRecentWithPlaceholders() {
        let drawer = WebHistoryDrawerView(placement: .trailing)
        drawer.update(saved: [], currentSavedId: nil, recent: [])
        #expect(drawer.rows(in: 0) == [.noSaved])
        #expect(drawer.rows(in: 1) == [.noRecent])

        let page = WebPage(title: "Apple", url: apple)
        let entry = WebHistoryEntry(url: wiki, title: "Eclipse", visitedAt: Date())
        drawer.update(saved: [page], currentSavedId: page.id, recent: [entry])
        #expect(drawer.rows(in: 0) == [.saved(page)])
        #expect(drawer.rows(in: 1) == [.recent(entry), .clearRecent])
    }

    @Test func drawerSitsAtTheRightEdgeOrAlongTheBottom() {
        let bounds = CGRect(x: 0, y: 0, width: 874, height: 402)
        let safe = UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
        let side = WebHistoryDrawerView.panelFrame(placement: .trailing, in: bounds, safe: safe)
        #expect(side.maxX == bounds.maxX)
        #expect(side.height == bounds.height)
        #expect(side.width < bounds.width * 0.61)

        let upright = CGRect(x: 0, y: 0, width: 402, height: 874)
        let bottom = WebHistoryDrawerView.panelFrame(placement: .bottom, in: upright, safe: .zero)
        #expect(bottom.maxY == upright.maxY)
        #expect(bottom.width == upright.width)
        #expect(bottom.height < upright.height * 0.7)
    }

    @Test func pickingARowClosesTheDrawerAndReportsIt() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let drawer = WebHistoryDrawerView(placement: .trailing)
        let entry = WebHistoryEntry(url: wiki, title: "Eclipse", visitedAt: Date())
        drawer.update(saved: [], currentSavedId: nil, recent: [entry])
        var picked: URL?
        var dismissed = false
        drawer.onSelectRecent = { picked = $0 }
        drawer.onDismiss = { dismissed = true }
        drawer.show(in: host, animated: false)
        #expect(drawer.superview === host)

        drawer.tableView(drawer.tableView, didSelectRowAt: IndexPath(row: 0, section: 1))
        #expect(picked == wiki)
        #expect(dismissed)
        #expect(drawer.superview == nil)
    }
}
