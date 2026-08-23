//
//  WebRemoteViewController+Chrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Safari-like Nav Chrome

extension WebRemoteViewController {

    /// Builds Back · host title · ⋯ · Close.
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

        bookmarksButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makeBookmarksMenu()
        )
        closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityHint =
            "Closes the browser. The TV keeps showing this site."
        navigationItem.rightBarButtonItems = [closeButton, bookmarksButton]
        setupOverlayChrome()
    }

    /// Camera-style Back / ⋯ / Close beside the Landscape preview (URL bar is hidden).
    func setupOverlayChrome() {
        overlayBackButton = makeOverlayChromeButton(
            systemName: "chevron.backward",
            accessibilityLabel: "Back"
        )
        overlayBackButton.addTarget(
            self,
            action: #selector(goBackTapped),
            for: .touchUpInside
        )
        overlayBookmarksButton = makeOverlayChromeButton(
            systemName: "ellipsis",
            accessibilityLabel: "More"
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
        overlayBackButton.isEnabled = false
        view.addSubview(overlayBackButton)
        view.addSubview(overlayBookmarksButton)
        view.addSubview(overlayCloseButton)
    }

    /// Landscape hides the URL nav bar; Vertical keeps it.
    func applyBrowserChromeMode(animated: Bool = false) {
        let overlay = usesOverlayBrowserChrome
        navigationController?.setNavigationBarHidden(overlay, animated: animated)
        overlayBackButton?.isHidden = !overlay
        overlayBookmarksButton?.isHidden = !overlay
        overlayCloseButton?.isHidden = !overlay
        applyWebStageTopConstraint()
        updateBrowserChrome()
        view.setNeedsLayout()
    }

    /// Places overlay Back / ⋯ / Close in a trailing column beside the Landscape card.
    func layoutOverlayChrome() {
        guard usesOverlayBrowserChrome, let panelView = webPanelView else { return }
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        let frames = PhoneWebViewportLayout.landscapeOverlayFrames(
            panel: panel,
            in: view.bounds,
            safeInsets: view.safeAreaInsets
        )
        overlayBackButton.frame = frames.back
        overlayBookmarksButton.frame = frames.more
        overlayCloseButton.frame = frames.close
        view.bringSubviewToFront(overlayBackButton)
        view.bringSubviewToFront(overlayBookmarksButton)
        view.bringSubviewToFront(overlayCloseButton)
    }

    /// Syncs the nav title, Back enabled state, and ⋯ checkmarks with `webView`.
    func updateBrowserChrome() {
        if usesOverlayBrowserChrome {
            navigationItem.title = nil
        } else if let url = webView?.url, !isBlankBrowserURL(url) {
            navigationItem.title = displayHost(for: url)
        } else {
            navigationItem.title = displayHost(for: page.url)
        }
        let canGoBack = webView.map {
            sessionBackRoot.shouldGoBack(
                backListCount: $0.backForwardList.backList.count
            )
        } ?? false
        backButton.isEnabled = canGoBack
        overlayBackButton?.isEnabled = canGoBack
        refreshBookmarksMenu()
    }

    /// Rebuilds the ⋯ menu (Refresh, New…, saved bookmarks).
    func refreshBookmarksMenu() {
        let menu = makeBookmarksMenu()
        bookmarksButton?.menu = menu
        overlayBookmarksButton?.menu = menu
    }

    private func makeOverlayChromeButton(
        systemName: String,
        accessibilityLabel: String
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
        return button
    }

    /// Navigates the phone web view like a normal browser load (Back keeps working).
    ///
    /// AirPlay is updated immediately so the TV follows; `didCommit` remains a backup.
    /// - Parameter pageId: Optional live-tile id when jumping to a saved site.
    func loadBrowserURL(_ url: URL, pageId: UUID? = nil) {
        sessionBackRoot.markUserNavigated()
        webView?.load(URLRequest(url: url))
        ExternalDisplayManager.shared.loadWeb(url: url, pageId: pageId ?? page.id)
        updateBrowserChrome()
    }

    /// Compact host label for the nav title.
    func displayHost(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return url.absoluteString
    }

    /// Alert to type a session URL (⋯ → New…; does not save a bookmark).
    func presentNewURLAlert() {
        if presentedViewController is UIAlertController { return }

        let alert = UIAlertController(
            title: "New Website",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] field in
            field.placeholder = "example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .URL
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .go
            if let url = self?.webView?.url, self?.isBlankBrowserURL(url) == false {
                field.text = url.absoluteString
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let raw = alert?.textFields?.first?.text ?? ""
            do {
                let url = try WebPageStore.normalizedHTTPSURL(from: raw)
                self.loadBrowserURL(url)
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

    private func makeBookmarksMenu() -> UIMenu {
        let refresh = UIAction(
            title: "Refresh",
            image: UIImage(systemName: "arrow.clockwise")
        ) { [weak self] _ in
            self?.reloadTapped()
        }
        let newURL = UIAction(
            title: "New…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.presentNewURLAlert()
        }

        let actions = UIMenu(title: "", options: .displayInline, children: [refresh, newURL])
        let saved = makeSavedWebsitesMenu()
        return UIMenu(children: [actions, saved])
    }

    private func makeSavedWebsitesMenu() -> UIMenu {
        let pages = WebPageStore.shared.pages
        if pages.isEmpty {
            return UIMenu(title: "", options: .displayInline, children: [
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
                self?.loadBrowserURL(bookmark.url, pageId: bookmark.id)
            }
        }
        return UIMenu(title: "", options: .displayInline, children: children)
    }

    /// Whether `bookmark` should show a checkmark for the active browser URL.
    private func isCurrentBookmark(_ bookmark: WebPage, currentURL: URL?) -> Bool {
        guard let currentURL, !isBlankBrowserURL(currentURL) else {
            return bookmark.id == page.id
        }
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
