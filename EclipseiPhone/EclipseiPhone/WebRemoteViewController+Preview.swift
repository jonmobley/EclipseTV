//
//  WebRemoteViewController+Preview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - Matched Viewport Browser

extension WebRemoteViewController: UIScrollViewDelegate, WKNavigationDelegate {

    /// Creates the phone web stage (9:16 or 16:9) and loads the page.
    ///
    /// The stage uses the same logical viewport as AirPlay so responsive sites
    /// reflow identically on phone and TV.
    func setupPreviewWebView() {
        let stage = UIView()
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(stage, at: 0)
        webStageView = stage

        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = PresentationViewController.mobileUserAgent
        web.scrollView.delegate = self
        web.navigationDelegate = self
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.isOpaque = true

        stage.addSubview(web)
        webView = web

        web.load(URLRequest(url: page.url))
    }

    /// Fits a Display Mode aspect panel inside the stage, then applies the shared
    /// logical web viewport (no TV rotation on the phone).
    func layoutPhoneWebViewport() {
        guard let stage = webStageView, let web = webView else { return }
        let bounds = stage.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = ExternalOutputSettings.displayModePanelRect(in: bounds)

        // Host the web view in an intermediate panel so layout math matches the TV.
        if webPanelView == nil {
            let panelView = UIView(frame: panel)
            panelView.backgroundColor = .black
            panelView.clipsToBounds = true
            stage.addSubview(panelView)
            webPanelView = panelView
            panelView.addSubview(web)
        }
        webPanelView?.frame = panel

        guard let panelView = webPanelView else { return }
        PresentationViewController.applyWebOutputLayout(
            to: web,
            in: panelView,
            rotationDegrees: 0
        )
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSyncingScroll, scrollView === webView?.scrollView else { return }
        let maxY = scrollView.contentSize.height - scrollView.bounds.height
        let progress = maxY > 0 ? min(max(scrollView.contentOffset.y / maxY, 0), 1) : 0
        ExternalDisplayManager.shared.setWebScrollProgress(progress)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 didCommit navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        ExternalDisplayManager.shared.loadWeb(url: url)
        if let title = webView.title, !title.isEmpty {
            self.title = title
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let title = webView.title, !title.isEmpty {
            self.title = title
        }
        let scroll = webView.scrollView
        let maxY = scroll.contentSize.height - scroll.bounds.height
        let progress = maxY > 0 ? min(max(scroll.contentOffset.y / maxY, 0), 1) : 0
        ExternalDisplayManager.shared.setWebScrollProgress(progress)
    }
}
