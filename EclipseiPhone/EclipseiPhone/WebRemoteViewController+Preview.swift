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

    /// Side inset so the rounded 16:9 / 9:16 card clears device corner radii.
    private var webPanelSideInset: CGFloat { 12 }

    /// Creates the phone web stage and adopts the warm page.
    ///
    /// Stage is full-bleed under the nav; the aspect card (Landscape 16:9 /
    /// Vertical 9:16) is laid out on top so sites match the AirPlay viewport.
    func setupPreviewWebView() {
        let stage = UIView()
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(stage, at: 0)
        webStageView = stage

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
            stage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Reuse a launch-warmed session so the page is already loaded.
        let web = WarmWebSessionPool.shared.adopt(page: page, into: self)
        web.translatesAutoresizingMaskIntoConstraints = true
        stage.addSubview(web)
        webView = web
    }

    /// Fits a Display Mode aspect panel inside the stage, then applies the shared
    /// logical web viewport (no TV rotation on the phone).
    ///
    /// Landscape → full-width 16:9 card (top-aligned). Vertical → full-width 9:16.
    func layoutPhoneWebViewport() {
        guard let stage = webStageView, let web = webView else { return }
        let bounds = stage.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = phoneWebPanelRect(in: bounds)

        // Host the web view in an intermediate panel so layout math matches the TV.
        if webPanelView == nil {
            let panelView = UIView(frame: panel)
            panelView.backgroundColor = .black
            panelView.clipsToBounds = true
            panelView.layer.cornerRadius = 32
            panelView.layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
            stage.addSubview(panelView)
            webPanelView = panelView
            web.translatesAutoresizingMaskIntoConstraints = true
            panelView.addSubview(web)
        }
        webPanelView?.frame = panel

        guard let panelView = webPanelView else { return }
        web.translatesAutoresizingMaskIntoConstraints = true
        PresentationViewController.applyWebOutputLayout(
            to: web,
            in: panelView,
            rotationDegrees: 0
        )
    }

    /// Display Mode card: Landscape locks 16:9; Vertical locks 9:16.
    ///
    /// Full width (minus a small side inset), top-aligned — same framing idea as
    /// Camera Live so horizontal shows read as a landscape stage on the phone.
    private func phoneWebPanelRect(in bounds: CGRect) -> CGRect {
        let inset = webPanelSideInset
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let width = max(0, bounds.width - inset * 2)
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            let fittedWidth = height * aspect
            return CGRect(
                x: bounds.midX - fittedWidth / 2,
                y: 0,
                width: fittedWidth,
                height: height
            )
        }
        return CGRect(
            x: inset,
            y: 0,
            width: width,
            height: height
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
        // Home Website defaults to Google, then tracks whatever the user opens next.
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
