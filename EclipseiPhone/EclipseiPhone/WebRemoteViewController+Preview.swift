//
//  WebRemoteViewController+Preview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - Matched Viewport Browser

extension WebRemoteViewController: UIScrollViewDelegate,
                                   WKNavigationDelegate,
                                   WKScriptMessageHandler {

    /// Inset from the safe area so the 9:16 / 16:9 panel clears device corner radii.
    private var webStageCornerInset: CGFloat { 12 }

    /// Creates the phone web stage (9:16 or 16:9) and loads the page.
    ///
    /// The stage uses the same logical viewport as AirPlay so responsive sites
    /// reflow identically on phone and TV. It sits inset inside the safe area so
    /// the centered panel is not clipped by rounded display corners.
    func setupPreviewWebView() {
        let stage = UIView()
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(stage, at: 0)
        webStageView = stage

        let inset = webStageCornerInset
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: guide.topAnchor, constant: inset),
            stage.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -inset),
            stage.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: inset),
            stage.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -inset)
        ])

        // Shared persistent store so logins survive close / reopen.
        // Media handler reports HTML5 play/pause/seek to the AirPlay WebView.
        let web = WKWebView(
            frame: .zero,
            configuration: EclipseWebKit.makeConfiguration(mediaHandler: self)
        )
        web.customUserAgent = PresentationViewController.mobileUserAgent
        web.scrollView.delegate = self
        web.navigationDelegate = self
        web.uiDelegate = self
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        // Stage is already inside the safe area; automatic insets leave a blank
        // strip that gets baked into home-grid thumbnails.
        web.scrollView.contentInsetAdjustmentBehavior = .never
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
        updateBrowserChrome()
        guard let url = webView.url else { return }
        ExternalDisplayManager.shared.loadWeb(url: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateBrowserChrome()
        let scroll = webView.scrollView
        let maxY = scroll.contentSize.height - scroll.bounds.height
        let progress = maxY > 0 ? min(max(scroll.contentOffset.y / maxY, 0), 1) : 0
        ExternalDisplayManager.shared.setWebScrollProgress(progress)
        // Refresh the home-grid preview from what the user is actually viewing.
        if let url = webView.url, url.scheme != "about" {
            WebThumbnailPrefetcher.shared.captureVisibleWebView(webView, for: page.id)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        updateBrowserChrome()
        presentWebLoadFailure(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        updateBrowserChrome()
        presentWebLoadFailure(error)
    }

    /// Surfaces a load failure unless the navigation was cancelled (e.g. new request).
    private func presentWebLoadFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        showPresentationToast("Couldn't load this page")
    }

    // MARK: - WKScriptMessageHandler (HTML5 media → AirPlay)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == EclipseWebMediaSync.messageName,
              let event = EclipseWebMediaSync.Event(messageBody: message.body) else {
            return
        }
        ExternalDisplayManager.shared.syncWebMedia(event)
    }
}
