//
//  BrowserTabListTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The browser opens one tab per website of the Show, the TV follows the active
//  tab, and a window a site opens stays on the phone until it is sent over.
//

import Testing
import WebKit
@testable import EclipseiPhone

struct BrowserTabListTests {

    private let a = WebPage(title: "A", url: URL(string: "https://a.example")!)
    private let b = WebPage(title: "B", url: URL(string: "https://b.example")!)
    private let c = WebPage(title: "C", url: URL(string: "https://c.example")!)

    @Test func showPagesBecomeTabsInOrderWithTheTappedOneActive() {
        let list = BrowserTabList(pages: [a, b, c], active: b)
        #expect(list.tabs.map { $0.page?.title } == ["A", "B", "C"])
        #expect(list.active.page?.id == b.id)
        #expect(list.tvTabId == list.active.id)
        #expect(list.showsStrip)
    }

    @Test func pageOutsideTheShowOpensInFront() {
        let list = BrowserTabList(pages: [a, b], active: c)
        #expect(list.tabs.map { $0.page?.title } == ["C", "A", "B"])
        #expect(list.active.page?.id == c.id)
    }

    @Test func duplicatePagesCollapse() {
        let list = BrowserTabList(pages: [a, a, b], active: a)
        #expect(list.tabs.count == 2)
    }

    @Test func singlePageShowsNoStrip() {
        let list = BrowserTabList(pages: [a], active: a)
        #expect(!list.showsStrip)
    }

    @Test func newTabLandsAfterTheActiveOne() {
        var list = BrowserTabList(pages: [a, b, c], active: a)
        let tab = BrowserTab.session(webView: nil)
        list.insert(tab, activate: true)
        #expect(list.tabs.map(\.id)[1] == tab.id)
        #expect(list.activeId == tab.id)
        #expect(!tab.isPhoneOnly)
        #expect(tab.title == "New Tab")
    }

    @Test func popupTabStaysOnThePhone() {
        var list = BrowserTabList(pages: [a], active: a)
        let popup = BrowserTab.popup(webView: nil)
        list.insert(popup, activate: true)
        #expect(popup.isPhoneOnly)
        #expect(list.active.id == popup.id)
        // The TV is still on the page that opened the window.
        #expect(list.tvTabId == list.tabs[0].id)
    }

    @Test func closingTheActiveTabPicksItsLeftNeighbour() {
        var list = BrowserTabList(pages: [a, b, c], active: b)
        #expect(list.close(id: list.activeId) != nil)
        #expect(list.active.page?.id == a.id)
        #expect(list.tabs.count == 2)
    }

    @Test func closingTheFirstActiveTabPicksTheNextOne() {
        var list = BrowserTabList(pages: [a, b], active: a)
        list.close(id: list.activeId)
        #expect(list.active.page?.id == b.id)
    }

    @Test func closingAnotherTabKeepsTheActiveOne() {
        var list = BrowserTabList(pages: [a, b, c], active: c)
        let removed = list.close(id: list.tab(pageId: a.id)!.id)
        #expect(removed?.page?.id == a.id)
        #expect(list.active.page?.id == c.id)
    }

    @Test func theLastTabCannotBeClosed() {
        var list = BrowserTabList(pages: [a], active: a)
        #expect(list.close(id: list.activeId) == nil)
        #expect(list.tabs.count == 1)
    }

    @Test func closingTheTVTabForgetsIt() {
        var list = BrowserTabList(pages: [a, b], active: a)
        list.close(id: list.activeId)
        #expect(list.tvTabId == nil)
    }
}
