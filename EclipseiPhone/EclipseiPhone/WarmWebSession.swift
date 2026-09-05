//
//  WarmWebSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit
import os.log

/// One warm `WKWebView` for a saved website card (bookmark or Show member).
///
/// Stays loaded off-screen (or in the home LiveHeader) so opening the page is
/// instant. Thread safety: main-actor only.
@MainActor
final class WarmWebSession: NSObject {

    /// Posted after `relinquish` so the home hero can reclaim the preview.
    static let didRelinquishNotification = Notification.Name("WarmWebSession.didRelinquish")

    let pageId: UUID
    private(set) var isAdopted = false

    /// One-shot callback fired once a warm load settles (loaded, failed, or already
    /// current). Lets the pool warm pages one at a time instead of all at once.
    var onWarmSettled: (() -> Void)?

    var currentURL: URL? { webView?.url }

    /// Last URL passed to `warm` / `adopt` (may precede `webView.url` while loading).
    private(set) var intendedURL: URL?

    /// Whether this session currently holds a live `WKWebView` (and web content process).
    var hasWebView: Bool { webView != nil }

    private var webView: WKWebView?
    private var hostView: UIView?
    /// Keeps overscroll gutters on the page colour for this session's web view.
    private var backgroundTint: WebBackgroundTint?
    private weak var mediaConsumer: WKScriptMessageHandler?
    private var settleWorkItem: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "WarmWeb")

    /// - Parameter pageId: Saved website id.
    init(pageId: UUID) {
        self.pageId = pageId
        super.init()
    }

    // MARK: - Public Interface

    /// Ensures the web view exists and has loaded `url` when idle.
    func warm(url: URL) {
        intendedURL = url
        let web = ensureWebView()
        guard !isAdopted else {
            settleWarm()
            return
        }
        if needsLoad(web: web, target: url) {
            logger.info("Warming page \(self.pageId.uuidString, privacy: .public)")
            web.load(URLRequest(url: url))
        } else {
            captureThumbnailIfPossible()
            settleWarm()
        }
    }

    /// Hands the warm web view to the phone browser.
    func adopt(into remote: WebRemoteViewController, url: URL) -> WKWebView {
        intendedURL = url
        let web = ensureWebView()
        isAdopted = true
        mediaConsumer = remote
        settleWorkItem?.cancel()
        settleWorkItem = nil

        web.navigationDelegate = remote
        web.uiDelegate = remote
        web.scrollView.delegate = remote
        web.removeFromSuperview()
        // Hero preview uses Auto Layout; the phone panel lays out by frame/transform.
        // Leaving `translatesAutoresizingMaskIntoConstraints == false` with no pins
        // collapses the web view to zero size (black stage).
        web.translatesAutoresizingMaskIntoConstraints = true
        web.autoresizingMask = []
        web.transform = .identity
        web.isUserInteractionEnabled = true

        if needsLoad(web: web, target: url) {
            web.load(URLRequest(url: url))
        }
        return web
    }

    /// Parks the web view after the phone browser closes.
    func relinquish(from remote: WebRemoteViewController) {
        guard isAdopted, mediaConsumer === remote, let web = webView else { return }
        web.scrollView.delegate = nil
        web.uiDelegate = nil
        web.navigationDelegate = self
        mediaConsumer = nil
        isAdopted = false
        park(web)
        captureThumbnailIfPossible()
        NotificationCenter.default.post(
            name: Self.didRelinquishNotification,
            object: self,
            userInfo: ["pageId": pageId]
        )
    }

    /// Moves the warm web view into a visible hero/preview host (no interaction).
    ///
    /// Bookmarks use the desktop logical viewport + scale (AirPlay parity).
    /// QuestPoll `/present` fills the host 1:1 so the page’s stage scaler is alone.
    /// - Parameter host: LiveHeader (or similar) content container.
    /// - Returns: Whether the preview was attached.
    @discardableResult
    func attachPreview(to host: UIView) -> Bool {
        guard !isAdopted, let web = webView else { return false }
        web.isUserInteractionEnabled = false
        web.navigationDelegate = self
        web.uiDelegate = nil
        web.scrollView.delegate = nil
        // Frame + transform layout (not Auto Layout) — matches AirPlay scale-up.
        web.translatesAutoresizingMaskIntoConstraints = true
        web.autoresizingMask = []
        if web.superview !== host {
            web.removeFromSuperview()
            host.addSubview(web)
        }
        layoutPreview(in: host)
        return true
    }

    /// Re-applies embed or desktop scaling when the hero host changes size.
    func layoutPreview(in host: UIView) {
        guard !isAdopted, let web = webView, web.superview === host else { return }
        let pageURL = intendedURL ?? web.url
        PresentationViewController.applyWebLayout(
            to: web,
            in: host,
            pageURL: pageURL,
            rotationDegrees: 0
        )
    }

    /// Returns the web view to the off-screen park host.
    func parkOffscreen() {
        guard !isAdopted, let web = webView else { return }
        web.isUserInteractionEnabled = true
        park(web)
    }

    /// Tears down the web view and detaches the off-screen host from the window.
    ///
    /// Required before dropping a session: the park host is a subview of the key
    /// window, so the window would otherwise keep the host — and through it the
    /// `WKWebView` and its web content process — alive for the life of the app.
    /// Safe to call repeatedly; the session can be re-warmed afterwards.
    func destroy() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        mediaConsumer = nil
        isAdopted = false

        if let web = webView {
            web.stopLoading()
            web.navigationDelegate = nil
            web.uiDelegate = nil
            web.scrollView.delegate = nil
            web.configuration.userContentController
                .removeScriptMessageHandler(forName: EclipseWebMediaSync.messageName)
            web.removeFromSuperview()
        }
        hostView?.removeFromSuperview()
        backgroundTint = nil
        webView = nil
        hostView = nil
    }

    // MARK: - Private Helpers

    /// Fires and clears the one-shot warm callback.
    private func settleWarm() {
        let settled = onWarmSettled
        onWarmSettled = nil
        settled?()
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }

        let size = parkSize()
        let host = UIView(
            frame: CGRect(x: -size.width, y: 0, width: size.width, height: size.height)
        )
        host.isUserInteractionEnabled = false
        host.alpha = 0.01

        let web = WKWebView(
            frame: host.bounds,
            configuration: EclipseWebKit.makeConfiguration(mediaHandler: self)
        )
        EclipseWebKit.applyDesktopSite(to: web)
        web.navigationDelegate = self
        web.isOpaque = true
        // Start black; `backgroundTint` replaces this once the page reports a colour.
        web.backgroundColor = WebBackgroundTint.fallback
        web.scrollView.backgroundColor = WebBackgroundTint.fallback
        web.scrollView.contentInsetAdjustmentBehavior = .never
        host.addSubview(web)

        keyWindow()?.addSubview(host)
        hostView = host
        webView = web
        backgroundTint = WebBackgroundTint(webView: web)
        return web
    }

    private func park(_ web: WKWebView) {
        let size = parkSize()
        let host: UIView
        if let existing = hostView {
            host = existing
            host.frame = CGRect(x: -size.width, y: 0, width: size.width, height: size.height)
        } else {
            host = UIView(
                frame: CGRect(x: -size.width, y: 0, width: size.width, height: size.height)
            )
            host.isUserInteractionEnabled = false
            host.alpha = 0.01
            hostView = host
            keyWindow()?.addSubview(host)
        }
        // Phone stage uses bounds + scale transform for the logical viewport.
        // Clear that before assigning frame — setting frame while transformed is
        // undefined and leaves bounds as a tiny corner, which is what the
        // thumbnail snapshot then captures (especially visible in Landscape).
        web.transform = .identity
        web.translatesAutoresizingMaskIntoConstraints = true
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.frame = CGRect(origin: .zero, size: size)
        web.isUserInteractionEnabled = true
        if web.superview !== host {
            web.removeFromSuperview()
            host.addSubview(web)
        }
        if host.superview == nil {
            keyWindow()?.addSubview(host)
        }
    }

    private func needsLoad(web: WKWebView, target: URL) -> Bool {
        guard let current = web.url else { return true }
        if current.absoluteString == "about:blank" || current.scheme == "about" {
            return true
        }
        return current.absoluteString != target.absoluteString
    }

    private func parkSize() -> CGSize {
        let logical = ExternalOutputSettings.webLogicalSize
        return CGSize(width: logical.width / 2, height: logical.height / 2)
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.session.role == .windowApplication })?
            .windows
            .first(where: \.isKeyWindow)
    }

    private func captureThumbnailIfPossible() {
        guard let web = webView, !isAdopted else { return }
        guard let url = web.url, url.scheme != "about" else { return }
        // Live Poll /present is a projector page, not a website tile. Capturing it
        // posted a thumbnail change and reloaded the Show grid, which dismissed
        // ⋯ menus while a room was live.
        if QuestPollConfig.isPresentURL(url) { return }
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let web = self.webView, !self.isAdopted else { return }
            WebThumbnailPrefetcher.shared.captureVisibleWebView(web, for: self.pageId)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

// MARK: - Warm-Phase Navigation

extension WarmWebSession: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        backgroundTint?.refresh()
        settleWarm()
        guard !isAdopted else { return }
        captureThumbnailIfPossible()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("Warm load failed: \(error.localizedDescription)")
        settleWarm()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("Warm provisional failed: \(error.localizedDescription)")
        settleWarm()
    }
}

// MARK: - Media Sync Forwarding

extension WarmWebSession: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        mediaConsumer?.userContentController(userContentController, didReceive: message)
    }
}
