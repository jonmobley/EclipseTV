//
//  WebRemoteViewController+Chrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Safari-like Nav Chrome

extension WebRemoteViewController {

    /// Builds Back · host title · ⊕ · Refresh · history · Close.
    /// ⊕ moves to the end of the tab chips while two or more tabs are open.
    func setupBrowserChrome() {
        backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(goBackTapped)
        )
        backButton.accessibilityLabel = "Back"
        backButton.isEnabled = false
        navigationItem.leftBarButtonItem = backButton
        navigationItem.titleView = nil

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance

        refreshBarButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadTapped)
        )
        refreshBarButton.accessibilityLabel = "Refresh"
        newTabBarButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(newTabTapped)
        )
        newTabBarButton.accessibilityLabel = "New Tab"
        sendToTVBarButton = UIBarButtonItem(
            image: UIImage(systemName: "tv"),
            style: .plain,
            target: self,
            action: #selector(sendToTVTapped)
        )
        sendToTVBarButton.accessibilityLabel = "Send to TV"
        if usesHistoryDrawer {
            bookmarksButton = UIBarButtonItem(
                image: UIImage(systemName: Self.bookmarksSymbol),
                style: .plain,
                target: self,
                action: #selector(historyTapped)
            )
        } else {
            bookmarksButton = UIBarButtonItem(
                image: UIImage(systemName: Self.bookmarksSymbol),
                menu: makeBookmarksMenu()
            )
        }
        bookmarksButton.accessibilityLabel = "History"
        closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityHint =
            "Closes the browser. The TV keeps showing this site."
        navigationItem.rightBarButtonItems = barTrailingItems()
        setupOverlayChrome()
    }

    /// Saved-websites button: a history clock, not a ⋯.
    static let bookmarksSymbol = "clock.arrow.circlepath"

    /// iPhone opens history as a drawer; iPad keeps a menu beside the button.
    var usesHistoryDrawer: Bool { traitCollection.userInterfaceIdiom != .pad }

    /// Whether ⊕ belongs in the button bar / column. With two or more tabs it sits
    /// at the end of the tab chips instead, like a desktop browser.
    var showsNewTabInChrome: Bool { !tabs.showsStrip }

    /// Right-to-left order of the nav bar's trailing items.
    private func barTrailingItems() -> [UIBarButtonItem] {
        var items: [UIBarButtonItem] = [closeButton, bookmarksButton, refreshBarButton]
        if showsNewTabInChrome {
            items.append(newTabBarButton)
        }
        if activeTab.isPhoneOnly {
            items.append(sendToTVBarButton)
        }
        return items
    }

    /// Camera-style buttons beside the Landscape card (URL bar is hidden).
    func setupOverlayChrome() {
        overlayBackButton = makeOverlayChromeButton(
            systemName: "chevron.backward",
            accessibilityLabel: "Back",
            action: #selector(goBackTapped)
        )
        overlayRefreshButton = makeOverlayChromeButton(
            systemName: "arrow.clockwise",
            accessibilityLabel: "Refresh",
            action: #selector(reloadTapped)
        )
        overlayNewTabButton = makeOverlayChromeButton(
            systemName: "plus",
            accessibilityLabel: "New Tab",
            action: #selector(newTabTapped)
        )
        overlaySendToTVButton = makeOverlayChromeButton(
            systemName: "tv",
            accessibilityLabel: "Send to TV",
            action: #selector(sendToTVTapped)
        )
        overlayBookmarksButton = makeOverlayChromeButton(
            systemName: Self.bookmarksSymbol,
            accessibilityLabel: "History",
            action: usesHistoryDrawer ? #selector(historyTapped) : nil
        )
        overlayBookmarksButton.showsMenuAsPrimaryAction = !usesHistoryDrawer
        overlayCloseButton = UIButton(type: .system)
        overlayCloseButton.applyPreviewCloseAppearance()
        overlayCloseButton.translatesAutoresizingMaskIntoConstraints = true
        overlayCloseButton.isHidden = true
        overlayCloseButton.accessibilityHint =
            "Closes the browser. The TV keeps showing this site."
        overlayCloseButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )
        for button in allOverlayChromeButtons {
            view.addSubview(button)
        }
    }

    /// Every overlay button.
    var allOverlayChromeButtons: [UIButton] {
        [
            overlayCloseButton, overlayBookmarksButton, overlayRefreshButton,
            overlayNewTabButton, overlaySendToTVButton, overlayBackButton
        ]
    }

    /// Landscape hides the URL nav bar; Vertical keeps it.
    func applyBrowserChromeMode(animated: Bool = false) {
        let overlay = usesOverlayBrowserChrome
        navigationController?.setNavigationBarHidden(overlay, animated: animated)
        applyOverlayChromeVisibility()
        applyWebStageTopConstraint()
        updateBrowserChrome()
        historyDrawer?.placement = historyDrawerPlacement
        view.setNeedsLayout()
    }

    /// Places the overlay buttons in a column beside the Landscape card, or in a
    /// row beneath it on an upright iPad. Back and Send to TV appear only when useful.
    func layoutOverlayChrome() {
        guard usesOverlayBrowserChrome, let panelView = webPanelView else { return }
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        let visible = visibleOverlayChromeButtons
        let frames = PhoneWebViewportLayout.overlayFrames(
            panel: panel,
            in: view.bounds,
            safeInsets: view.safeAreaInsets,
            placement: overlayChromePlacement,
            showsTabStrip: tabs.showsStrip,
            count: visible.count
        )
        applyOverlayChromeVisibility()
        for (button, frame) in zip(visible, frames) {
            button.frame = frame
            view.bringSubviewToFront(button)
        }
        // The history drawer covers the buttons while it is open.
        if let drawer = historyDrawer, drawer.superview === view {
            view.bringSubviewToFront(drawer)
        }
    }

    /// Shows the overlay buttons that earn a slot (Landscape only), hides the rest.
    func applyOverlayChromeVisibility() {
        let visible = usesOverlayBrowserChrome ? visibleOverlayChromeButtons : []
        for button in allOverlayChromeButtons {
            button.isHidden = !visible.contains(where: { $0 === button })
        }
    }

    /// Overlay buttons that currently earn a slot, top to bottom: Close · history ·
    /// Refresh, then ⊕ (single tab only; otherwise it ends the tab chips), Send to TV
    /// and Back only while they apply, so the fixed three never move.
    var visibleOverlayChromeButtons: [UIButton] {
        var buttons: [UIButton] = [
            overlayCloseButton, overlayBookmarksButton, overlayRefreshButton
        ]
        if showsNewTabInChrome {
            buttons.append(overlayNewTabButton)
        }
        if activeTab.isPhoneOnly {
            buttons.append(overlaySendToTVButton)
        }
        if canGoBackInSession {
            buttons.append(overlayBackButton)
        }
        return buttons
    }

    /// Column beside the card on a phone; a browser-style top bar on iPad.
    var overlayChromePlacement: PhoneWebViewportLayout.ChromePlacement {
        PhoneWebViewportLayout.chromePlacement(
            for: view.bounds.size,
            isVertical: ExternalOutputSettings.isVerticalMode,
            idiom: traitCollection.userInterfaceIdiom
        )
    }

    /// Whether the active tab has in-session history behind the current page.
    var canGoBackInSession: Bool {
        webView.map {
            sessionBackRoot.shouldGoBack(
                backListCount: $0.backForwardList.backList.count
            )
        } ?? false
    }

    /// Syncs the nav title, Back, ⊕, Send to TV, and the history checkmarks with the active tab.
    func updateBrowserChrome() {
        if usesOverlayBrowserChrome {
            navigationItem.title = nil
        } else if let url = webView?.url, !isBlankBrowserURL(url) {
            navigationItem.title = displayHost(for: url)
        } else if let page = activeTab.page {
            navigationItem.title = displayHost(for: page.url)
        } else {
            navigationItem.title = activeTab.title
        }
        let canGoBack = canGoBackInSession
        backButton.isEnabled = canGoBack
        overlayBackButton?.isEnabled = canGoBack
        applyOverlayChromeVisibility()
        let wanted = barTrailingItems()
        let current = navigationItem.rightBarButtonItems ?? []
        if !wanted.elementsEqual(current, by: ===) {
            navigationItem.rightBarButtonItems = wanted
        }
        refreshBookmarksMenu()
        if usesOverlayBrowserChrome {
            layoutOverlayChrome()
        }
    }

    /// Rebuilds the history menu (iPad) or the open drawer's rows (iPhone).
    func refreshBookmarksMenu() {
        if usesHistoryDrawer {
            refreshHistoryDrawer()
            return
        }
        let menu = makeBookmarksMenu()
        bookmarksButton?.menu = menu
        overlayBookmarksButton?.menu = menu
    }

    // MARK: - History drawer (iPhone)

    /// Beside a Landscape card the drawer comes in from the right; in Vertical, from below.
    var historyDrawerPlacement: WebHistoryDrawerView.Placement {
        usesOverlayBrowserChrome ? .trailing : .bottom
    }

    @objc func historyTapped() {
        presentHistoryDrawer()
    }

    func presentHistoryDrawer() {
        guard historyDrawer == nil else { return }
        let drawer = WebHistoryDrawerView(placement: historyDrawerPlacement)
        drawer.onSelectSaved = { [weak self] page in self?.openSavedPage(page) }
        drawer.onSelectRecent = { [weak self] url in self?.openRecentPage(url) }
        drawer.onClearRecent = { [weak self] in
            WebHistoryStore.shared.clear()
            self?.refreshHistoryDrawer()
        }
        drawer.onDismiss = { [weak self, weak drawer] in
            if self?.historyDrawer === drawer { self?.historyDrawer = nil }
        }
        historyDrawer = drawer
        refreshHistoryDrawer()
        drawer.show(in: view)
    }

    func refreshHistoryDrawer() {
        historyDrawer?.update(
            saved: WebPageStore.shared.pages,
            currentSavedId: currentSavedPageId,
            recent: WebHistoryStore.shared.entries
        )
    }

    /// The saved website the active tab is showing, for the checkmark.
    private var currentSavedPageId: UUID? {
        let currentURL = webView?.url
        return WebPageStore.shared.pages.first {
            isCurrentBookmark($0, currentURL: currentURL)
        }?.id
    }

    /// A recent page: its tab when one is already on it, else it loads in the
    /// active tab (like Safari history), and the TV follows as for a link.
    func openRecentPage(_ url: URL) {
        if let open = tabs.tabs.first(where: {
            $0.webView?.url.map { WebHistoryStore.sameAddress($0, url) } ?? false
        }) {
            activateTab(id: open.id)
            return
        }
        guard let webView else {
            openNewTab(url: url)
            return
        }
        // A page the user picked is real Back history, like following a link.
        activeTab.backRoot.markUserNavigated()
        webView.load(URLRequest(url: url))
    }

    func makeOverlayChromeButton(
        systemName: String,
        accessibilityLabel: String,
        action: Selector?
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.image = UIImage(systemName: systemName, withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 12, bottom: 10, trailing: 12
        )
        let button = UIButton(configuration: config)
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = true
        button.isHidden = true
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        return button
    }

    /// Compact host label for the nav title.
    func displayHost(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return url.absoluteString
    }

    /// Alert to type an address for a new tab (⊕; does not save a bookmark).
    func presentNewURLAlert() {
        if presentedViewController is UIAlertController { return }

        let alert = UIAlertController(
            title: "New Tab",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .URL
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .go
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let raw = alert?.textFields?.first?.text ?? ""
            do {
                let url = try WebPageStore.normalizedHTTPSURL(from: raw)
                self.openNewTab(url: url)
            } catch {
                let errorAlert = UIAlertController(
                    title: "Invalid Address",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Bookmarks Menu

    /// Saved websites from the library; each opens in its own tab.
    private func makeBookmarksMenu() -> UIMenu {
        let pages = WebPageStore.shared.pages
        let currentURL = webView?.url
        var saved: [UIMenuElement] = pages.map { bookmark in
            let state: UIMenuElement.State =
                isCurrentBookmark(bookmark, currentURL: currentURL) ? .on : .off
            return UIAction(
                title: bookmark.title,
                subtitle: bookmark.url.host,
                state: state
            ) { [weak self] _ in
                self?.openSavedPage(bookmark)
            }
        }
        if saved.isEmpty {
            saved = [UIAction(title: "No saved websites", attributes: .disabled) { _ in }]
        }
        var sections: [UIMenuElement] = [
            UIMenu(title: "Saved", options: .displayInline, children: saved)
        ]
        let recent = WebHistoryStore.shared.entries.prefix(10).map { entry in
            UIAction(
                title: entry.title,
                subtitle: WebHistoryStore.fallbackTitle(for: entry.url),
                image: UIImage(systemName: "clock")
            ) { [weak self] _ in
                self?.openRecentPage(entry.url)
            }
        }
        if !recent.isEmpty {
            sections.append(UIMenu(title: "Recent", options: .displayInline, children: recent))
        }
        return UIMenu(children: sections)
    }

    /// Whether `bookmark` should show a checkmark for the active tab.
    private func isCurrentBookmark(_ bookmark: WebPage, currentURL: URL?) -> Bool {
        if let pageId = activeTab.page?.id {
            return bookmark.id == pageId
        }
        guard let currentURL, !isBlankBrowserURL(currentURL) else { return false }
        return Self.urlsMatchForMenu(currentURL, bookmark.url)
    }

    /// Host-level match so www differences still check the current item.
    private static func urlsMatchForMenu(_ a: URL, _ b: URL) -> Bool {
        guard let aHost = a.host?.lowercased(), let bHost = b.host?.lowercased() else {
            return a.absoluteString == b.absoluteString
        }
        let stripWWW: (String) -> String = {
            $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0
        }
        return stripWWW(aHost) == stripWWW(bHost) && a.path == b.path
    }
}
