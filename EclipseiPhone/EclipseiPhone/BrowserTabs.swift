//
//  BrowserTabs.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import WebKit

/// One tab in the phone browser.
///
/// A saved tab shows a website card of the open Show and borrows its warm web view
/// from `WarmWebSessionPool` while the browser is open. A session tab (⊕ New Tab, or
/// a window a site opened) owns its own web view and is gone when the browser closes.
final class BrowserTab {

    let id: UUID
    /// Saved website this tab shows, or nil for a session tab.
    let page: WebPage?
    /// Web view a session tab owns. Saved tabs get theirs from the warm pool.
    var ownWebView: WKWebView?
    /// Warm web view a saved tab has borrowed from the pool (nil until first shown).
    var borrowedWebView: WKWebView?
    /// Whichever web view currently backs this tab.
    var webView: WKWebView? { ownWebView ?? borrowedWebView }
    /// True while the tab shows only on the phone (a window a site opened, until the
    /// user sends it to the TV). Sign-in pages must never land on the big screen.
    var isPhoneOnly: Bool
    /// Host of the current page, for session tabs without a saved title.
    var hostTitle: String?
    /// Opening-load history depth; recaptured until the user navigates.
    var backRoot = BrowserSessionBackRoot()

    private init(id: UUID, page: WebPage?, ownWebView: WKWebView?, isPhoneOnly: Bool) {
        self.id = id
        self.page = page
        self.ownWebView = ownWebView
        self.isPhoneOnly = isPhoneOnly
    }

    /// Tab for a website card of the Show.
    static func saved(_ page: WebPage) -> BrowserTab {
        BrowserTab(id: UUID(), page: page, ownWebView: nil, isPhoneOnly: false)
    }

    /// Tab the user opened with ⊕ (mirrors to the TV like any site).
    static func session(webView: WKWebView?) -> BrowserTab {
        BrowserTab(id: UUID(), page: nil, ownWebView: webView, isPhoneOnly: false)
    }

    /// Tab for a window a site opened (`window.open` / `target=_blank`): phone only.
    static func popup(webView: WKWebView?) -> BrowserTab {
        BrowserTab(id: UUID(), page: nil, ownWebView: webView, isPhoneOnly: true)
    }

    var isSaved: Bool { page != nil }

    /// Chip title: the saved name, else the host, else a placeholder.
    var title: String {
        if let page { return page.title }
        if let hostTitle, !hostTitle.isEmpty { return hostTitle }
        return "New Tab"
    }
}

/// The browser's open tabs, which one is active, and which one the TV is showing.
struct BrowserTabList {

    private(set) var tabs: [BrowserTab]
    private(set) var activeId: UUID
    /// Tab whose page the TV was last told to show.
    var tvTabId: UUID?

    /// Opens one tab per Show website in Show order, with `active` selected.
    ///
    /// `active` is added in front when it is not one of `pages` (a site opened from
    /// Home or the Websites list rather than from a Show).
    /// - Parameter previewOnly: Opens `active` on the phone only, with nothing on the
    ///   TV, until the user sends it (History browses; it never takes output).
    init(pages: [WebPage], active: WebPage, previewOnly: Bool = false) {
        var seen = Set<UUID>()
        var list = pages.filter { seen.insert($0.id).inserted }.map(BrowserTab.saved)
        var activeTab = list.first { $0.page?.id == active.id }
        if activeTab == nil {
            let tab = BrowserTab.saved(active)
            list.insert(tab, at: 0)
            activeTab = tab
        }
        tabs = list
        activeId = activeTab!.id
        if previewOnly {
            activeTab!.isPhoneOnly = true
            tvTabId = nil
        } else {
            tvTabId = activeTab!.id
        }
    }

    var active: BrowserTab {
        tabs.first { $0.id == activeId } ?? tabs[0]
    }

    var activeIndex: Int {
        tabs.firstIndex { $0.id == activeId } ?? 0
    }

    /// The strip only earns its space once there is something to switch between.
    var showsStrip: Bool { tabs.count > 1 }

    func tab(id: UUID) -> BrowserTab? {
        tabs.first { $0.id == id }
    }

    func tab(pageId: UUID) -> BrowserTab? {
        tabs.first { $0.page?.id == pageId }
    }

    func tab(webView: WKWebView) -> BrowserTab? {
        tabs.first { $0.webView === webView }
    }

    /// Makes `id` the active tab. No-op for an unknown id.
    mutating func activate(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeId = id
    }

    /// Adds a tab after the active one (where a new Safari tab lands).
    mutating func insert(_ tab: BrowserTab, activate: Bool) {
        tabs.insert(tab, at: activeIndex + 1)
        if activate {
            activeId = tab.id
        }
    }

    /// Removes a tab; the last tab cannot be closed.
    ///
    /// Closing the active tab activates its left neighbour (the right one when it
    /// was first), as Safari does.
    /// - Returns: The removed tab, or nil when nothing changed.
    @discardableResult
    mutating func close(id: UUID) -> BrowserTab? {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = tabs.remove(at: index)
        if activeId == id {
            activeId = tabs[max(index - 1, 0)].id
        }
        if tvTabId == id {
            tvTabId = nil
        }
        return removed
    }
}
