//
//  WebRemoteViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

/// Phone-side Safari-like browser for a page presented on AirPlay.
///
/// Stages a 9:16 (Vertical) or 16:9 (Landscape) panel matching the AirPlay
/// viewport. Compact chrome: Back · URL pill with inline Reload · bookmarks.
final class WebRemoteViewController: UIViewController {

    // MARK: - Properties

    let page: WebPage
    var webView: WKWebView?
    /// Full-bleed black host behind the aspect-fitted web panel.
    var webStageView: UIView?
    /// Aspect-fitted panel (9:16 or 16:9) that hosts the web view.
    var webPanelView: UIView?
    /// Suppresses scroll sync while applying programmatic scroll changes.
    var isSyncingScroll = false

    /// Pill that holds the URL field + inline reload (Safari-style).
    let urlBarContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 22
        view.clipsToBounds = true
        return view
    }()

    let urlField: UITextField = {
        let field = UITextField()
        field.placeholder = "Search or enter website"
        field.textAlignment = .center
        field.borderStyle = .none
        field.font = .systemFont(ofSize: 17, weight: .medium)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
        field.textContentType = .URL
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    let reloadButton: UIButton = {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        config.image = UIImage(systemName: "arrow.clockwise", withConfiguration: symbol)
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 10
        )
        config.baseForegroundColor = .label
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    var backButton: UIBarButtonItem!
    var bookmarksButton: UIBarButtonItem!

    // MARK: - Init

    /// Creates a presenting browser for the given saved page.
    init(page: WebPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        setupBrowserChrome()
        setupPreviewWebView()
        observePresentationChanges()
        updateBrowserChrome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ExternalDisplayManager.shared.refreshConnection()
        refreshBookmarksMenu()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Free-browse starts blank — jump straight into the address field.
        if page.isFreeBrowse, isBlankBrowserURL(webView?.url ?? page.url) {
            urlField.becomeFirstResponder()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutURLBarWidth()
        layoutPhoneWebViewport()
    }

    // Closing the phone browser does not stop AirPlay — the site stays live.

    /// Whether `url` is the empty free-browse start page.
    func isBlankBrowserURL(_ url: URL) -> Bool {
        url.absoluteString == "about:blank" || url.scheme == "about"
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc func closeTapped() {
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc func goBackTapped() {
        if webView?.canGoBack == true {
            webView?.goBack()
        } else {
            // First page: Back leaves the browser (Safari-compact chrome has no X).
            closeTapped()
        }
    }

    @objc func reloadTapped() {
        webView?.reload()
        ExternalDisplayManager.shared.reloadWeb()
    }

    @objc func webEndedExternally() {
        closeTapped()
    }

    @objc func outputSettingsChanged() {
        layoutPhoneWebViewport()
        webView?.reload()
        ExternalDisplayManager.shared.reloadWeb()
    }

    @objc func bookmarksStoreChanged() {
        refreshBookmarksMenu()
    }

    // MARK: - Observers

    private func observePresentationChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webEndedExternally),
            name: ExternalDisplayManager.webDidEndNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(outputSettingsChanged),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksStoreChanged),
            name: WebPageStore.didChangeNotification,
            object: nil
        )
    }
}
