//
//  WebPopupViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

/// Phone-only modal browser for `window.open` / `target=_blank` (e.g. OAuth).
///
/// Uses the exact `WKWebViewConfiguration` WebKit supplies so opener linkage and
/// cookies stay tied to the parent page. Navigations are never mirrored to AirPlay.
final class WebPopupViewController: UIViewController {

    // MARK: - Properties

    let webView: WKWebView

    // MARK: - Init

    /// Creates a popup browser from WebKit's `createWebViewWith` configuration.
    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        EclipseWebKit.applyDesktopSite(to: webView)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .systemBackground
        webView.isOpaque = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - Presentation

    /// Wraps this popup in a page-sheet nav controller and presents it.
    ///
    /// Walks to the topmost presented controller so nested `window.open`
    /// calls can stack another sheet.
    static func present(
        from presenter: UIViewController,
        configuration: WKWebViewConfiguration
    ) -> WKWebView {
        let popup = WebPopupViewController(configuration: configuration)
        let nav = UINavigationController(rootViewController: popup)
        nav.modalPresentationStyle = .pageSheet
        var host = presenter
        while let presented = host.presentedViewController {
            host = presented
        }
        host.present(nav, animated: true)
        return popup.webView
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    // MARK: - Chrome

    private func updateTitle() {
        guard let url = webView.url else {
            title = "Sign In"
            return
        }
        if let host = url.host, !host.isEmpty {
            title = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            title = "Sign In"
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebPopupViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateTitle()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateTitle()
    }
}

// MARK: - WKUIDelegate

extension WebPopupViewController: WKUIDelegate {

    func webViewDidClose(_ webView: WKWebView) {
        dismiss(animated: true)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        WebPopupViewController.present(from: self, configuration: configuration)
    }
}
