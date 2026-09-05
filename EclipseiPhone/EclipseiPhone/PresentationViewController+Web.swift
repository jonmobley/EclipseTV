//
//  PresentationViewController+Web.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - Web Presentation

extension PresentationViewController: WKNavigationDelegate {

    /// Lazily creates and returns the external-display web view.
    func ensureWebView() -> WKWebView {
        if let webView = webView { return webView }

        // Same persistent store + process pool as the phone browser.
        let view = WKWebView(
            frame: .zero,
            configuration: EclipseWebKit.makeConfiguration()
        )
        EclipseWebKit.applyDesktopSite(to: view)
        view.navigationDelegate = self
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        // Start black; `webBackgroundTint` replaces this once the page reports a colour.
        view.backgroundColor = WebBackgroundTint.fallback
        view.scrollView.backgroundColor = WebBackgroundTint.fallback
        // Non-interactive on the TV; the phone preview drives scrolling/navigation.
        view.isUserInteractionEnabled = false

        webContainer.addSubview(view)
        webView = view
        webBackgroundTint = WebBackgroundTint(webView: view)
        return view
    }

    /// Shows `url` on the external web view and applies Vertical/scale layout.
    ///
    /// Called from the transition commit, so the page that just painted on the
    /// overlay is adopted as primary rather than loaded a second time.
    func showWeb(url: URL) {
        hideCamera()
        hidePDF()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()

        webContainer.isHidden = false
        adoptIncomingWebView(loadedWith: url)
        let view = ensureWebView()
        applyWebLayout()

        if webRequestedURL != url {
            webRequestedURL = url
            view.load(URLRequest(url: url))
        }
    }

    /// Promotes the overlay's web view to primary, replacing any older primary.
    ///
    /// The overlay view already holds the rendered page. Reloading it into a
    /// separate primary view showed a blank primary the moment the overlay was
    /// dropped, and paid the network twice.
    /// - Parameter url: What the overlay view was asked to load.
    private func adoptIncomingWebView(loadedWith url: URL) {
        guard let incoming = incomingWebView else { return }
        incomingWebView = nil
        incomingWebNavigation = nil
        if let old = webView, old !== incoming {
            old.stopLoading()
            old.navigationDelegate = nil
            old.removeFromSuperview()
        }
        incoming.navigationDelegate = self
        if incoming.superview !== webContainer {
            incoming.removeFromSuperview()
            webContainer.addSubview(incoming)
        }
        if webView !== incoming {
            webView = incoming
            webRequestedURL = url
            webBackgroundTint = WebBackgroundTint(webView: incoming)
        }
    }

    /// Returns the overlay web view to wherever it belongs when a transition is
    /// cancelled or finished without a web commit.
    ///
    /// A borrowed primary (see `installIncomingWeb`) goes back to `webContainer`
    /// still loaded; a throwaway overlay view is destroyed.
    func discardIncomingWebView() {
        guard let incoming = incomingWebView else { return }
        incomingWebView = nil
        incomingWebNavigation = nil
        if incoming === webView {
            incoming.removeFromSuperview()
            webContainer.addSubview(incoming)
            return
        }
        incoming.stopLoading()
        incoming.navigationDelegate = nil
        incoming.removeFromSuperview()
    }

    /// Hides the web view without destroying it (keeps process warm for reconnect).
    func hideWeb() {
        webContainer.isHidden = true
        webView?.transform = .identity
        webView?.bounds = .zero
    }

    /// Tears down the web view entirely (Stop / clear).
    func teardownWeb() {
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView?.removeFromSuperview()
        webView = nil
        webRequestedURL = nil
        webBackgroundTint = nil
        webContainer.isHidden = true
        if case .web = presentedSource?.content { presentedSource = nil }
    }

    /// Applies present-embed or desktop scale-up + portrait rotation.
    func applyWebLayout() {
        guard !webContainer.isHidden, let webView = webView else { return }
        Self.applyWebLayout(
            to: webView,
            in: webContainer,
            pageURL: webView.url
        )
    }

    /// Loads `url` into the live web view without tearing down the overlay.
    func loadWeb(url: URL) {
        guard !webContainer.isHidden else {
            showWeb(url: url)
            return
        }
        let view = ensureWebView()
        if webRequestedURL != url {
            webRequestedURL = url
            view.load(URLRequest(url: url))
        }
    }

    /// Sets the page scroll offset to match the phone browser (1:1 logical space).
    func setWebContentOffset(_ offset: CGPoint) {
        guard let webView = webView, !webContainer.isHidden else { return }
        let scroll = webView.scrollView
        let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        let clamped = CGPoint(
            x: min(max(0, offset.x), maxX),
            y: min(max(0, offset.y), maxY)
        )
        if scroll.contentOffset != clamped {
            scroll.contentOffset = clamped
        }
    }

    /// Sets vertical scroll from normalized progress (0...1) for mismatched viewports.
    func setWebScrollProgress(_ progress: CGFloat) {
        guard let webView = webView, !webContainer.isHidden else { return }
        let scroll = webView.scrollView
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        let clampedProgress = min(max(progress, 0), 1)
        let offset = CGPoint(x: scroll.contentOffset.x, y: clampedProgress * maxY)
        if scroll.contentOffset != offset {
            scroll.contentOffset = offset
        }
    }

    /// Reloads the current page.
    func reloadWeb() {
        webView?.reload()
    }

    /// Scrolls the page to the top.
    func scrollWebToTop() {
        guard let webView = webView else { return }
        webView.scrollView.setContentOffset(.zero, animated: false)
        webView.evaluateJavaScript("window.scrollTo(0, 0);", completionHandler: nil)
    }

    /// Applies a phone HTML5 media event to the external WebView (play/pause/seek).
    func applyWebMediaSync(_ event: EclipseWebMediaSync.Event) {
        guard let webView, !webContainer.isHidden else { return }
        if event.action == "play"
            || (event.action == "timeupdate" && !event.paused)
            || (event.action == "seeked" && !event.paused) {
            configureAudioSession(muted: event.muted)
        }
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = EclipseWebMediaSync.applyJavaScript(jsonPayload: json)
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
