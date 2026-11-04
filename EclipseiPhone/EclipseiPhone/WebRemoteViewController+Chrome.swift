//
//  WebRemoteViewController+Chrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Safari-like Nav Chrome

extension WebRemoteViewController {

    /// Builds Back · host title · Refresh · ⊕ · ⋯ · Close.
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
        bookmarksButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makeBookmarksMenu()
        )
        bookmarksButton.accessibilityLabel = "Websites"
        closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityHint =
            "Closes the browser. The TV keeps showing this site."
        navigationItem.rightBarButtonItems = barTrailingItems(showsSendToTV: false)
        setupOverlayChrome()
    }

    /// Right-to-left order of the nav bar's trailing items.
    private func barTrailingItems(showsSendToTV: Bool) -> [UIBarButtonItem] {
        var items: [UIBarButtonItem] = [closeButton, bookmarksButton, refreshBarButton, newTabBarButton]
        if showsSendToTV {
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
            systemName: "ellipsis",
            accessibilityLabel: "Websites",
            action: nil
        )
        overlayBookmarksButton.showsMenuAsPrimaryAction = true
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
    }

    /// Shows the overlay buttons that earn a slot (Landscape only), hides the rest.
    func applyOverlayChromeVisibility() {
        let visible = usesOverlayBrowserChrome ? visibleOverlayChromeButtons : []
        for button in allOverlayChromeButtons {
            button.isHidden = !visible.contains(where: { $0 === button })
        }
    }

    /// Overlay buttons that currently earn a slot, top to bottom: Close · ⋯ · Refresh · ⊕,
    /// then Send to TV and Back only while they apply, so the fixed four never move.
    var visibleOverlayChromeButtons: [UIButton] {
        var buttons: [UIButton] = [
            overlayCloseButton, overlayBookmarksButton, overlayRefreshButton, overlayNewTabButton
        ]
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

    /// Syncs the nav title, Back, Send to TV, and the ⋯ checkmarks with the active tab.
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
        let wantsSendToTV = activeTab.isPhoneOnly
        let showsSendToTV = navigationItem.rightBarButtonItems?
            .contains(where: { $0 === sendToTVBarButton }) ?? false
        if wantsSendToTV != showsSendToTV {
            navigationItem.rightBarButtonItems = barTrailingItems(showsSendToTV: wantsSendToTV)
        }
        refreshBookmarksMenu()
        if usesOverlayBrowserChrome {
            layoutOverlayChrome()
        }
    }

    /// Rebuilds the ⋯ menu (saved websites).
    func refreshBookmarksMenu() {
        let menu = makeBookmarksMenu()
        bookmarksButton?.menu = menu
        overlayBookmarksButton?.menu = menu
    }

    private func makeOverlayChromeButton(
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
        if pages.isEmpty {
            return UIMenu(children: [
                UIAction(
                    title: "No saved websites",
                    attributes: .disabled
                ) { _ in }
            ])
        }

        let currentURL = webView?.url
        let children: [UIMenuElement] = pages.map { bookmark in
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
        return UIMenu(children: children)
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
