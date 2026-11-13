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
    /// Tab chips above the card.
    static let tabStripHeight: CGFloat = 34
    static let tabStripGap: CGFloat = 6
    /// Trailing strip for the Landscape button column, outside the 16:9 card.
    static var landscapeChromeColumn: CGFloat { overlayButtonSize + 16 }
    /// Top bar on iPad: tab chips on the left, buttons on the right, card beneath.
    static var topBarHeight: CGFloat { overlayButtonSize + overlayButtonGap }

    /// Where the Landscape buttons go.
    enum ChromePlacement: Equatable {
        /// Beside the card, down the right: a turned phone has no height to spare.
        case trailingColumn
        /// A browser-style bar above the card, buttons at the top right: iPad, in
        /// either orientation (iPadOS never turns the app for us).
        case topRow
    }

    /// Phones use the column; iPads the top bar. Vertical Shows keep the nav bar
    /// and never use overlay chrome.
    static func chromePlacement(
        for bounds: CGSize,
        isVertical: Bool,
        idiom: UIUserInterfaceIdiom
    ) -> ChromePlacement {
        if isVertical { return .trailingColumn }
        return idiom == .pad ? .topRow : .trailingColumn
    }

    /// Insets from the stage edges in to the card.
    static func panelInsets(
        isVertical: Bool,
        safe: UIEdgeInsets,
        placement: ChromePlacement = .trailingColumn,
        showsTabStrip: Bool = false
    ) -> UIEdgeInsets {
        let strip = showsTabStrip ? tabStripHeight + tabStripGap : 0
        if isVertical {
            return UIEdgeInsets(top: strip, left: sideInset, bottom: 0, right: sideInset)
        }
        switch placement {
        case .trailingColumn:
            // The card may touch the top edge; chips above it get a little air.
            return UIEdgeInsets(
                top: showsTabStrip ? strip + 8 : 0,
                left: max(safe.left, sideInset),
                bottom: max(safe.bottom, sideInset),
                right: max(safe.right, sideInset) + landscapeChromeColumn
            )
        case .topRow:
            // The bar holds the chips too, so the strip costs no extra height.
            return UIEdgeInsets(
                top: max(safe.top, sideInset) + topBarHeight,
                left: max(safe.left, sideInset),
                bottom: max(safe.bottom, sideInset),
                right: max(safe.right, sideInset)
            )
        }
    }

    /// Display Mode card: Landscape locks 16:9; Vertical locks 9:16.
    ///
    /// Landscape centres the card and its button column together, between the safe
    /// edges. (It used to left-align the card, which piled all the spare width on the
    /// right around the column.) Under a top bar the card sits just beneath it, centred.
    static func panelRect(
        in bounds: CGRect,
        isVertical: Bool,
        safeInsets: UIEdgeInsets,
        aspect: CGFloat,
        placement: ChromePlacement = .trailingColumn,
        showsTabStrip: Bool = false
    ) -> CGRect {
        let available = bounds.inset(
            by: panelInsets(
                isVertical: isVertical,
                safe: safeInsets,
                placement: placement,
                showsTabStrip: showsTabStrip
            )
        )
        guard available.width > 1, available.height > 1 else { return .zero }

        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        let topAligned = isVertical || placement == .topRow
        let y = topAligned ? available.minY : available.midY - height / 2
        let x: CGFloat
        if topAligned {
            x = available.midX - width / 2
        } else {
            // `available` already leaves the column's width on the right; centre the
            // card plus that column within the full span between the safe edges.
            let regionWidth = available.width + landscapeChromeColumn
            let groupWidth = width + landscapeChromeColumn
            x = available.minX + max((regionWidth - groupWidth) / 2, 0)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Tab chips directly above the card, as wide as the card.
    static func tabStripFrame(above panel: CGRect) -> CGRect {
        CGRect(
            x: panel.minX,
            y: panel.minY - tabStripGap - tabStripHeight,
            width: panel.width,
            height: tabStripHeight
        )
    }

    /// Tab chips: above the card (column), or on the left of the top bar, stopping
    /// short of the `buttonCount` buttons at its right (top bar).
    static func tabStripFrame(
        panel: CGRect,
        in bounds: CGRect,
        safeInsets: UIEdgeInsets,
        placement: ChromePlacement,
        buttonCount: Int
    ) -> CGRect {
        switch placement {
        case .trailingColumn:
            return tabStripFrame(above: panel)
        case .topRow:
            let buttons = overlayFrames(
                panel: panel, in: bounds, safeInsets: safeInsets,
                placement: .topRow, count: buttonCount
            )
            let barTop = max(safeInsets.top, sideInset)
            let rightLimit = (buttons.map(\.minX).min() ?? bounds.maxX) - 12
            return CGRect(
                x: panel.minX,
                y: barTop + (overlayButtonSize - tabStripHeight) / 2,
                width: max(rightLimit - panel.minX, 0),
                height: tabStripHeight
            )
        }
    }

    /// Frames for `count` visible buttons, in order: stacked down the trailing strip
    /// outside `panel`, or right-aligned along the top bar with the first button in
    /// the corner.
    ///
    /// The column starts level with the tab strip when one is shown, so Close stays
    /// at the top corner.
    static func overlayFrames(
        panel: CGRect,
        in bounds: CGRect,
        safeInsets: UIEdgeInsets,
        placement: ChromePlacement = .trailingColumn,
        showsTabStrip: Bool = false,
        count: Int
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        let size = overlayButtonSize
        let gap = overlayButtonGap
        switch placement {
        case .trailingColumn:
            // Right beside the card, so the two read as one centred group.
            let colX = panel.maxX + (landscapeChromeColumn - size) / 2
            let firstY = showsTabStrip ? tabStripFrame(above: panel).minY : panel.minY
            let top = max(firstY, safeInsets.top + 8)
            return (0..<count).map { index in
                CGRect(
                    x: colX,
                    y: top + CGFloat(index) * (size + gap),
                    width: size,
                    height: size
                )
            }
        case .topRow:
            let right = bounds.maxX - max(safeInsets.right, sideInset)
            let y = max(safeInsets.top, sideInset)
            return (0..<count).map { index in
                CGRect(
                    x: right - size - CGFloat(index) * (size + gap),
                    y: y,
                    width: size,
                    height: size
                )
            }
        }
    }

    /// Back · ⋯ · Close stacked in the trailing strip, outside `panel`.
    static func landscapeOverlayFrames(
        panel: CGRect,
        in bounds: CGRect,
        safeInsets: UIEdgeInsets
    ) -> (back: CGRect, more: CGRect, close: CGRect) {
        let frames = overlayFrames(
            panel: panel, in: bounds, safeInsets: safeInsets, count: 3
        )
        return (frames[0], frames[1], frames[2])
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

        let strip = BrowserTabStripView()
        strip.translatesAutoresizingMaskIntoConstraints = true
        strip.isHidden = true
        strip.onSelect = { [weak self] id in self?.activateTab(id: id) }
        strip.onClose = { [weak self] id in self?.closeTab(id: id) }
        stage.addSubview(strip)
        tabStripView = strip

        // Reuse a launch-warmed session so the page is already loaded.
        attachActiveTab()
        refreshTabStrip()
    }

    /// Pushes same-document URL changes (pushState / hash routing) to the TV.
    ///
    /// `didCommit` only fires for full document loads, so a single-page site could
    /// route the phone to a new view while the external display stayed on the entry
    /// URL. Full loads are left to `didCommit`: while one is in flight, `url` reports
    /// the provisional (pre-redirect) address, which is not the page the TV should load.
    func observeSameDocumentNavigation(_ web: WKWebView) {
        webURLObservation = web.observe(\.url, options: [.new]) { [weak self] web, _ in
            MainActor.assumeIsolated {
                guard let self, web === self.webView, !web.isLoading,
                      let url = web.url, !self.isBlankBrowserURL(url) else { return }
                self.tab(for: web)?.hostTitle = self.displayHost(for: url)
                self.updateBrowserChrome()
                self.refreshTabStrip()
                self.mirrorActiveTab(url: url)
            }
        }
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
        updateOrientationCover()
        guard let stage = webStageView, let web = webView else { return }
        let bounds = stage.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = phoneWebPanelRect(in: bounds)
        if let strip = tabStripView {
            strip.frame = PhoneWebViewportLayout.tabStripFrame(
                panel: panel,
                in: bounds,
                safeInsets: view.safeAreaInsets,
                placement: overlayChromePlacement,
                buttonCount: visibleOverlayChromeButtons.count
            )
            stage.bringSubviewToFront(strip)
        }

        // Host the web view in an intermediate panel so layout math matches the TV.
        if webPanelView == nil {
            let panelView = UIView(frame: panel)
            panelView.backgroundColor = .black
            panelView.clipsToBounds = true
            // Same card treatment as the hero preview: 16pt corners, 1pt grey hairline.
            panelView.layer.cornerRadius = 16
            panelView.layer.borderWidth = 1
            panelView.layer.borderColor = UIColor.separator
                .resolvedColor(with: traitCollection).cgColor
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
        if activeTab.isPhoneOnly {
            // Nothing on the TV to match: fill the card 1:1 so a sign-in form is
            // readable instead of a scaled-down desktop page.
            web.transform = .identity
            web.frame = panelView.bounds
            return
        }
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
            aspect: ExternalOutputSettings.orientation.aspectRatio,
            placement: overlayChromePlacement,
            showsTabStrip: tabs.showsStrip
        )
    }

    // MARK: - External Display Sync

    /// Sends the browser's normalized scroll position to the external display.
    ///
    /// Normalized rather than absolute: the TV renders the same logical viewport at a
    /// different scale, so its content height need not match the phone's exactly.
    func pushWebScrollProgress() {
        guard mirrorsActiveTab, let scroll = webView?.scrollView else { return }
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
        guard manager.isWebLive, mirrorsActiveTab else { return }
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

    /// A finger on the page holds Auto Scroll; a tap resumes it.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === webView?.scrollView else { return }
        autoScroller.pause()
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if BrowserSessionBackRoot.isUserMainFrameNavigation(navigationAction) {
            tab(for: webView)?.backRoot.markUserNavigated()
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 didCommit navigation: WKNavigation!) {
        if let url = webView.url, !isBlankBrowserURL(url) {
            tab(for: webView)?.hostTitle = displayHost(for: url)
        }
        refreshTabStrip()
        guard webView === self.webView else { return }
        // A new page starts from its top, by hand.
        autoScroller.stop()
        captureBrowserSessionRootIfNeeded()
        updateBrowserChrome()
        guard let url = webView.url else { return }
        mirrorActiveTab(url: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, !isBlankBrowserURL(url) {
            tab(for: webView)?.hostTitle = displayHost(for: url)
        }
        refreshTabStrip()
        guard webView === self.webView else { return }
        captureBrowserSessionRootIfNeeded()
        updateBrowserChrome()
        pushWebScrollProgress()
        if let url = webView.url, url.scheme != "about", let pageId = activeTab.page?.id {
            WebThumbnailPrefetcher.shared.captureVisibleWebView(webView, for: pageId)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        guard webView === self.webView else { return }
        updateBrowserChrome()
        presentWebLoadFailure(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard webView === self.webView else { return }
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
              message.webView === webView, mirrorsActiveTab,
              let event = EclipseWebMediaSync.Event(messageBody: message.body) else {
            return
        }
        ExternalDisplayManager.shared.syncWebMedia(event)
        AudioAmbientPolicy.applyYieldIfNeeded(forWebMedia: event)
    }
}
