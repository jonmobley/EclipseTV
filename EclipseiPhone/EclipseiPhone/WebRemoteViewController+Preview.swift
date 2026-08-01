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
    /// The card's size changes with the device orientation but its logical viewport does
    /// not, so rotating never reflows the page or moves it out of step with the TV.
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
    /// Vertical is a full-width card top-aligned under the nav bar. Landscape runs on a
    /// turned phone, so the card is the largest 16:9 that fits and is centred in the
    /// stage — same framing idea as Camera Live.
    private func phoneWebPanelRect(in bounds: CGRect) -> CGRect {
        let isVertical = ExternalOutputSettings.isVerticalMode
        let available = bounds.inset(by: webPanelInsets(isVertical: isVertical))
        guard available.width > 1, available.height > 1 else { return .zero }

        let aspect = ExternalOutputSettings.orientation.aspectRatio
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        let y = isVertical ? available.minY : available.midY - height / 2
        return CGRect(
            x: available.midX - width / 2,
            y: y,
            width: width,
            height: height
        )
    }

    /// Insets from the stage edges in to the card.
    ///
    /// The stage already begins below the nav bar, so only the sides and bottom need the
    /// device safe area — and only in Landscape, where turning the phone puts the sensor
    /// housing and home indicator along the card's long edges.
    private func webPanelInsets(isVertical: Bool) -> UIEdgeInsets {
        let inset = webPanelSideInset
        guard !isVertical else {
            return UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        }
        let safe = view.safeAreaInsets
        return UIEdgeInsets(
            top: 0,
            left: max(safe.left, inset),
            bottom: max(safe.bottom, inset),
            right: max(safe.right, inset)
        )
    }

    // MARK: - External Display Sync

    /// Sends the browser's normalized scroll position to the external display.
    ///
    /// Normalized rather than absolute: the TV renders the same logical viewport at a
    /// different scale, so its content height need not match the phone's exactly.
    func pushWebScrollProgress() {
        guard let scroll = webView?.scrollView else { return }
        let maxY = scroll.contentSize.height - scroll.bounds.height
        let progress = maxY > 0 ? min(max(scroll.contentOffset.y / maxY, 0), 1) : 0
        ExternalDisplayManager.shared.setWebScrollProgress(progress)
    }

    /// Re-asserts URL and scroll position on the external display after a rotation.
    ///
    /// Turning the phone changes the window scene's geometry, which iOS can answer by
    /// re-offering the external scene, so the TV is told where the page is again rather
    /// than assumed to still match.
    func resyncExternalWeb() {
        let manager = ExternalDisplayManager.shared
        manager.refreshConnection()
        // Only re-assert an overlay that is already ours; never claim the display back
        // from whatever replaced this page.
        guard manager.isWebLive else { return }
        if let url = webView?.url, !isBlankBrowserURL(url) {
            manager.loadWeb(url: url)
        }
        pushWebScrollProgress()
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSyncingScroll, scrollView === webView?.scrollView else { return }
        pushWebScrollProgress()
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
        pushWebScrollProgress()
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
        AudioAmbientPolicy.applyYieldIfNeeded(forWebMedia: event)
    }
}
