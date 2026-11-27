//
//  MacRemoteWebViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - MacRemoteWebViewController

/// Shows Eclipse-for-Mac's own remote page, edge to edge, as the Mac remote.
///
/// The page is the remote: preview, tiles, Lock, Blackout, tools and Music all
/// come from the Mac, so a new control added there appears here with no app
/// update. The app adds only a Back arrow (see ``MacRemotePage``).
///
/// Thread Safety: Main thread only.
final class MacRemoteWebViewController: UIViewController {

    // MARK: - Properties

    /// The operator asked to leave the remote.
    var onClose: (() -> Void)?
    /// The Mac could not be reached or refused the page; the text is for the operator.
    var onFailure: ((String) -> Void)?

    private let info: RemoteConnectInfo
    private var webView: WKWebView?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let fallbackCloseButton = UIButton(type: .system)
    private var hasPageBackArrow = false
    private var isPINCardUp = false
    private var hasShownPage = false

    /// Sign-in for the Mac remote, kept apart from the app's website browser so
    /// a site opened there can never be sent the remote's cookie.
    private static let dataStoreID = UUID(
        uuidString: "6C0E2B6E-5A1F-4B7C-9E57-ECA1B5E0A001"
    )

    static let unreachableMessage =
        "Couldn't reach Eclipse on the Mac. Check that this device is on the same "
        + "Wi‑Fi and that Eclipse Remote is turned on in the Mac's Settings."

    // MARK: - Initialization

    init(info: RemoteConnectInfo) {
        self.info = info
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installWebView()
        installSpinner()
        installFallbackCloseButton()
        load()
    }

    // MARK: - Private Helpers

    private func installWebView() {
        let configuration = WKWebViewConfiguration()
        if let id = Self.dataStoreID {
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        } else {
            configuration.websiteDataStore = .nonPersistent()
        }
        let content = configuration.userContentController
        content.add(
            WeakScriptMessageHandler(delegate: self), name: MacRemotePage.messageHandlerName
        )
        content.addUserScript(
            WKUserScript(
                source: MacRemotePage.backArrowScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.underPageBackgroundColor = .black
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        // The page lays itself out around the notch and home bar (viewport-fit=cover).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.alpha = 0
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.webView = webView
    }

    private func installSpinner() {
        spinner.color = .white
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// Shown while the page is loading, while its PIN card covers the header, or
    /// if the page has no header to carry the Back arrow: always a way out.
    private func installFallbackCloseButton() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.backward")
        config.baseForegroundColor = .white
        fallbackCloseButton.configuration = config
        fallbackCloseButton.accessibilityLabel = "Back"
        fallbackCloseButton.addAction(
            UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside
        )
        fallbackCloseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fallbackCloseButton)
        NSLayoutConstraint.activate([
            fallbackCloseButton.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4
            ),
            fallbackCloseButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4
            ),
            fallbackCloseButton.widthAnchor.constraint(equalToConstant: 44),
            fallbackCloseButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func load() {
        guard let url = MacRemotePage.url(for: info) else {
            onFailure?(Self.unreachableMessage)
            return
        }
        // A Mac that is off or on another network would otherwise spin for a minute.
        webView?.load(URLRequest(url: url, timeoutInterval: 10))
    }

    private func showPage() {
        hasShownPage = true
        spinner.stopAnimating()
        syncFallbackCloseButton()
        UIView.animate(withDuration: 0.2) { self.webView?.alpha = 1 }
    }

    /// The app's own Back button shows whenever the page's arrow can't be reached.
    private func syncFallbackCloseButton() {
        fallbackCloseButton.isHidden = hasShownPage && hasPageBackArrow && !isPINCardUp
    }

    private func fail() {
        // Once the remote is on screen a blip is the page's to ride out (it
        // reconnects by itself); only a failed first load goes back to Connect.
        guard !hasShownPage else { return }
        onFailure?(Self.unreachableMessage)
    }
}

// MARK: - WKNavigationDelegate

extension MacRemoteWebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        MacRemotePage.allowsNavigation(
            to: navigationAction.request.url, base: info.baseURL
        ) ? .allow : .cancel
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame,
              let http = navigationResponse.response as? HTTPURLResponse,
              http.statusCode >= 400 else { return .allow }
        fail()
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showPage()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail()
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        fail()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS reclaimed the page's memory; the saved sign-in brings it straight back.
        webView.reload()
    }
}

// MARK: - WKScriptMessageHandler

extension MacRemoteWebViewController: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame,
              let raw = message.body as? String,
              let kind = MacRemotePage.Message(rawValue: raw) else { return }
        switch kind {
        case .headerReady:
            hasPageBackArrow = true
        case .headerMissing:
            hasPageBackArrow = false
        case .pinShown:
            isPINCardUp = true
        case .pinHidden:
            isPINCardUp = false
        case .close:
            onClose?()
            return
        }
        syncFallbackCloseButton()
    }
}
