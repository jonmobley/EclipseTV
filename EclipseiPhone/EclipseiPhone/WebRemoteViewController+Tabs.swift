//
//  WebRemoteViewController+Tabs.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - Tabs

extension WebRemoteViewController {

    /// Whether what the active tab does should reach the TV.
    var mirrorsActiveTab: Bool { !activeTab.isPhoneOnly }

    /// Puts the active tab's web view on the stage (first open and every switch).
    ///
    /// A saved tab borrows its warm web view from the pool, keeping whatever page it
    /// had navigated to. A session tab brings its own.
    func attachActiveTab() {
        guard let stage = webStageView else { return }
        let tab = activeTab
        let web: WKWebView
        if let own = tab.ownWebView {
            web = own
        } else if let page = tab.page {
            let current = WarmWebSessionPool.shared.currentURL(for: page.id)
                .flatMap { isBlankBrowserURL($0) ? nil : $0 }
            web = WarmWebSessionPool.shared.adopt(page: page, into: self, url: current)
            tab.borrowedWebView = web
        } else {
            return
        }
        web.translatesAutoresizingMaskIntoConstraints = true
        if web.superview !== (webPanelView ?? stage) {
            web.removeFromSuperview()
            (webPanelView ?? stage).addSubview(web)
        }
        webView = web
        installAutoScrollTapIfNeeded()
        observeSameDocumentNavigation(web)
        captureBrowserSessionRootIfNeeded()
        layoutPhoneWebViewport()
        updateBrowserChrome()
    }

    /// Takes the active tab's web view off the stage; the tab keeps it.
    func detachActiveTab() {
        autoScroller.stop()
        webURLObservation = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    /// Switches to `id`; the TV follows unless the tab is phone-only.
    func activateTab(id: UUID) {
        guard id != tabs.activeId, tabs.tab(id: id) != nil else { return }
        detachActiveTab()
        tabs.activate(id: id)
        attachActiveTab()
        sendActiveTabToTVIfNeeded()
        refreshTabStrip()
    }

    /// Shows a saved website: its tab when it has one, else a new tab for it.
    func openSavedPage(_ page: WebPage) {
        if let existing = tabs.tab(pageId: page.id) {
            activateTab(id: existing.id)
            return
        }
        detachActiveTab()
        tabs.insert(BrowserTab.saved(page), activate: true)
        attachActiveTab()
        sendActiveTabToTVIfNeeded()
        refreshTabStrip()
    }

    /// Opens `url` in a new tab (⊕). The TV follows once the page commits.
    func openNewTab(url: URL) {
        let web = WKWebView(
            frame: .zero,
            configuration: EclipseWebKit.makeConfiguration(mediaHandler: self)
        )
        EclipseWebKit.applyDesktopSite(to: web)
        configureOwnWebView(web)
        detachActiveTab()
        tabs.insert(BrowserTab.session(webView: web), activate: true)
        attachActiveTab()
        web.load(URLRequest(url: url))
        refreshTabStrip()
    }

    /// Opens a window a site asked for (`window.open` / `target=_blank`) as a
    /// phone-only tab, using the exact configuration WebKit supplies so opener
    /// linkage and cookies stay tied to the parent page.
    func openPopupTab(configuration: WKWebViewConfiguration) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: configuration)
        EclipseWebKit.applyDesktopSite(to: web)
        configureOwnWebView(web)
        detachActiveTab()
        tabs.insert(BrowserTab.popup(webView: web), activate: true)
        attachActiveTab()
        refreshTabStrip()
        return web
    }

    private func configureOwnWebView(_ web: WKWebView) {
        web.navigationDelegate = self
        web.uiDelegate = self
        web.scrollView.delegate = self
        web.isOpaque = true
        web.backgroundColor = .white
    }

    /// Closes a tab. The last tab stays; the Close button closes the browser.
    func closeTab(id: UUID) {
        guard tabs.tabs.count > 1, let tab = tabs.tab(id: id) else { return }
        let wasActive = id == tabs.activeId
        if wasActive {
            detachActiveTab()
        }
        tabs.close(id: id)
        dispose(tab)
        if wasActive {
            attachActiveTab()
            sendActiveTabToTVIfNeeded()
        }
        refreshTabStrip()
    }

    /// Sends a phone-only tab to the TV; from then on it mirrors like any tab.
    func sendActiveTabToTV() {
        guard activeTab.isPhoneOnly else { return }
        activeTab.isPhoneOnly = false
        layoutPhoneWebViewport()
        sendActiveTabToTVIfNeeded()
        updateBrowserChrome()
        refreshTabStrip()
    }

    /// Tells the TV to show the active tab when it is on another one.
    ///
    /// A tab that has not loaded yet reports in from `didCommit` instead.
    func sendActiveTabToTVIfNeeded() {
        let tab = activeTab
        guard !tab.isPhoneOnly, tabs.tvTabId != tab.id else { return }
        guard let url = webView?.url, !isBlankBrowserURL(url) else { return }
        mirrorActiveTab(url: url)
        pushWebScrollProgress()
    }

    /// Loads `url` on the TV for the active tab, when it mirrors.
    ///
    /// Passing the saved page id moves the live stroke to that Show card. Session tabs
    /// keep the stroke on the website the browser opened with.
    func mirrorActiveTab(url: URL) {
        guard mirrorsActiveTab else { return }
        tabs.tvTabId = activeTab.id
        ExternalDisplayManager.shared.loadWeb(
            url: url,
            pageId: activeTab.page?.id ?? initialPage.id
        )
    }

    /// Returns every saved tab's warm web view to the pool and drops own web views.
    func relinquishAllTabs() {
        tabs.tabs.forEach(dispose)
    }

    private func dispose(_ tab: BrowserTab) {
        if let page = tab.page, tab.borrowedWebView != nil {
            WarmWebSessionPool.shared.relinquish(pageId: page.id, from: self)
            tab.borrowedWebView = nil
        }
        if let own = tab.ownWebView {
            own.stopLoading()
            own.removeFromSuperview()
            own.navigationDelegate = nil
            own.uiDelegate = nil
            own.scrollView.delegate = nil
            tab.ownWebView = nil
        }
    }

    /// Tab backed by `webView`, for delegate callbacks from any tab.
    func tab(for webView: WKWebView) -> BrowserTab? {
        tabs.tab(webView: webView)
    }

    /// Rebuilds the chips; the strip shows only with two or more tabs.
    func refreshTabStrip() {
        guard let strip = tabStripView else { return }
        let showsStrip = tabs.showsStrip
        let changed = strip.isHidden == showsStrip
        strip.isHidden = !showsStrip
        strip.update(tabs: tabs.tabs, activeId: tabs.activeId, tvTabId: tabs.tvTabId)
        if changed {
            layoutPhoneWebViewport()
        }
    }
}
