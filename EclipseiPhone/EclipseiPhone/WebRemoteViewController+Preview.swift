//
//  WebRemoteViewController+Preview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

/// Phone-browser 16:9 / 9:16 card geometry (matches AirPlay, independent of chrome).
enum PhoneWebViewportLayout {
    static let sideInset: CGFloat = 12
    static let overlayButtonSize: CGFloat = 44
    static let overlayButtonGap: CGFloat = 8
    /// Trailing strip for Landscape Back / ⋯ / Close, outside the 16:9 card.
    static var landscapeChromeColumn: CGFloat { overlayButtonSize + 16 }

    /// Insets from the stage edges in to the card.
    static func panelInsets(isVertical: Bool, safe: UIEdgeInsets) -> UIEdgeInsets {
        if isVertical {
            return UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
        }
        return UIEdgeInsets(
            top: 0,
            left: max(safe.left, sideInset),
            bottom: max(safe.bottom, sideInset),
            right: max(safe.right, sideInset) + landscapeChromeColumn
        )
    }

    /// Display Mode card: Landscape locks 16:9; Vertical locks 9:16.
    ///
    /// Landscape left-aligns the card so chrome can sit in the trailing column.
    static func panelRect(
        in bounds: CGRect,
        isVertical: Bool,
        safeInsets: UIEdgeInsets,
        aspect: CGFloat
    ) -> CGRect {
        let available = bounds.inset(
            by: panelInsets(isVertical: isVertical, safe: safeInsets)
        )
        guard available.width > 1, available.height > 1 else { return .zero }

        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        let y = isVertical ? available.minY : available.midY - height / 2
        let x = isVertical ? available.midX - width / 2 : available.minX
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Back · ⋯ · Close stacked in the trailing strip, outside `panel`.
    static func landscapeOverlayFrames(
        panel: CGRect,
        in bounds: CGRect,
        safeInsets: UIEdgeInsets
    ) -> (back: CGRect, more: CGRect, close: CGRect) {
        let size = overlayButtonSize
        let gap = overlayButtonGap
        let stripMinX = panel.maxX
        let stripMaxX = bounds.maxX - max(safeInsets.right, sideInset)
        let colX = stripMinX + max((stripMaxX - stripMinX - size) / 2, 0)
        let top = max(panel.minY, safeInsets.top + 8)
        let back = CGRect(x: colX, y: top, width: size, height: size)
        let more = CGRect(x: colX, y: back.maxY + gap, width: size, height: size)
        let close = CGRect(x: colX, y: more.maxY + gap, width: size, height: size)
        return (back, more, close)
    }
}

// MARK: - Matched Viewport Browser

extension WebRemoteViewController: UIScrollViewDelegate,
                                   WKNavigationDelegate,
                                   WKScriptMessageHandler {

    /// Creates the phone web stage and adopts the warm page.
    ///
    /// Vertical: stage sits under the URL nav bar. Landscape: full-bleed so the
    /// 16:9 card can fill the height; chrome sits in the trailing column.
    func setupPreviewWebView() {
        let stage = UIView()
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(stage, at: 0)
        webStageView = stage

        let guide = view.safeAreaLayoutGuide
        verticalStageTopConstraint = stage.topAnchor.constraint(
            equalTo: guide.topAnchor, constant: 6
        )
        landscapeStageTopConstraint = stage.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            stage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        applyWebStageTopConstraint()

        // Reuse a launch-warmed session so the page is already loaded.
        let web = WarmWebSessionPool.shared.adopt(page: page, into: self)
        web.translatesAutoresizingMaskIntoConstraints = true
        stage.addSubview(web)
        webView = web
        captureBrowserSessionRootIfNeeded()
    }

    /// Pins the stage under the nav bar (Vertical) or full-bleed (Landscape).
    func applyWebStageTopConstraint() {
        let overlay = usesOverlayBrowserChrome
        landscapeStageTopConstraint?.isActive = overlay
        verticalStageTopConstraint?.isActive = !overlay
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
        layoutOverlayChrome()

        guard let panelView = webPanelView else { return }
        web.translatesAutoresizingMaskIntoConstraints = true
        PresentationViewController.applyWebLayout(
            to: web,
            in: panelView,
            pageURL: web.url,
            rotationDegrees: 0
        )
    }

    /// Display Mode card: Landscape locks 16:9; Vertical locks 9:16.
    private func phoneWebPanelRect(in bounds: CGRect) -> CGRect {
        PhoneWebViewportLayout.panelRect(
            in: bounds,
            isVertical: ExternalOutputSettings.isVerticalMode,
            safeInsets: view.safeAreaInsets,
            aspect: ExternalOutputSettings.orientation.aspectRatio
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if BrowserSessionBackRoot.isUserMainFrameNavigation(navigationAction) {
            sessionBackRoot.markUserNavigated()
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 didCommit navigation: WKNavigation!) {
        captureBrowserSessionRootIfNeeded()
        updateBrowserChrome()
        guard let url = webView.url else { return }
        ExternalDisplayManager.shared.loadWeb(url: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureBrowserSessionRootIfNeeded()
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
