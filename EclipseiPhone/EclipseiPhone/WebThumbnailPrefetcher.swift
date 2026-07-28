//
//  WebThumbnailPrefetcher.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit
import os.log

/// Loads saved websites off-screen to capture page snapshots (and favicons).
///
/// Started on app launch so home-grid tiles fill in without opening each site.
@MainActor
final class WebThumbnailPrefetcher: NSObject, WKNavigationDelegate {

    static let shared = WebThumbnailPrefetcher()

    private var queue: [WebPage] = []
    private var isRunning = false
    private var webView: WKWebView?
    private var hostView: UIView?
    private var currentPage: WebPage?
    private var settleWorkItem: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "WebThumbnailPrefetch")

    private override init() {
        super.init()
    }

    /// Enqueues every saved page (launch / store change).
    func prefetchAllSavedPages() {
        enqueue(WebPageStore.shared.pages)
    }

    /// Adds pages to the capture queue (deduped by id).
    func enqueue(_ pages: [WebPage]) {
        for page in pages {
            if queue.contains(where: { $0.id == page.id }) { continue }
            if currentPage?.id == page.id { continue }
            queue.append(page)
            fetchFavicon(for: page)
        }
        pump()
    }

    /// Captures from an already-loaded on-screen browser (best preview quality).
    func captureVisibleWebView(_ webView: WKWebView, for pageId: UUID) {
        takeSnapshot(from: webView, pageId: pageId)
    }

    // MARK: - Queue

    private func pump() {
        guard !isRunning, let page = queue.first else { return }
        queue.removeFirst()
        isRunning = true
        currentPage = page
        let web = ensureWebView()
        logger.info("Prefetch \(page.title, privacy: .public)")
        web.load(URLRequest(url: page.url))
    }

    private func finishCurrent() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        currentPage = nil
        isRunning = false
        if queue.isEmpty {
            tearDownHost()
        } else {
            pump()
        }
    }

    // MARK: - Host WebView

    private func snapshotSize() -> CGSize {
        let logical = ExternalOutputSettings.webLogicalSize
        // Retina-ish pixels without being huge.
        let scale: CGFloat = 2
        return CGSize(width: logical.width * scale / 2, height: logical.height * scale / 2)
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }

        let size = snapshotSize()
        let host = UIView(frame: CGRect(x: -size.width, y: 0, width: size.width, height: size.height))
        host.isUserInteractionEnabled = false
        host.alpha = 0.01

        let web = WKWebView(frame: host.bounds, configuration: EclipseWebKit.makeConfiguration())
        web.customUserAgent = PresentationViewController.mobileUserAgent
        web.navigationDelegate = self
        web.isOpaque = true
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        // Host is window-attached; automatic safe-area insets leave a white band
        // at the top of every snapshot.
        web.scrollView.contentInsetAdjustmentBehavior = .never
        host.addSubview(web)

        if let window = keyWindow() {
            window.addSubview(host)
        }

        hostView = host
        webView = web
        return web
    }

    private func tearDownHost() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        hostView?.removeFromSuperview()
        webView = nil
        hostView = nil
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.session.role == .windowApplication })?
            .windows
            .first(where: \.isKeyWindow)
    }

    // MARK: - Snapshot / Favicon

    private func scheduleSnapshot() {
        settleWorkItem?.cancel()
        let pageId = currentPage?.id
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let web = self.webView, let pageId else {
                self.finishCurrent()
                return
            }
            self.takeSnapshot(from: web, pageId: pageId) {
                self.finishCurrent()
            }
        }
        settleWorkItem = work
        // Let the page paint after didFinish before capturing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func takeSnapshot(
        from webView: WKWebView,
        pageId: UUID,
        completion: (() -> Void)? = nil
    ) {
        let scroll = webView.scrollView
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = .zero
        scroll.verticalScrollIndicatorInsets = .zero
        scroll.horizontalScrollIndicatorInsets = .zero

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.takeSnapshot(with: config) { image, error in
            Task { @MainActor in
                if let image {
                    WebThumbnailStore.shared.saveSnapshot(image, for: pageId)
                } else if let error {
                    self.logger.error("Snapshot failed: \(error.localizedDescription)")
                }
                completion?()
            }
        }
    }

    private func fetchFavicon(for page: WebPage) {
        guard WebThumbnailStore.shared.snapshot(for: page.id) == nil,
              WebThumbnailStore.shared.favicon(for: page.id) == nil,
              let host = page.url.host else { return }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/s2/favicons"
        components.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128")
        ]
        guard let url = components.url else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    WebThumbnailStore.shared.saveFavicon(image, for: page.id)
                }
            } catch {
                // Favicon is best-effort.
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleSnapshot()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("Prefetch failed: \(error.localizedDescription)")
        finishCurrent()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("Prefetch provisional failed: \(error.localizedDescription)")
        finishCurrent()
    }
}
