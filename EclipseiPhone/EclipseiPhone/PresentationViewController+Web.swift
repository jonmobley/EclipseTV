//
//  PresentationViewController+Web.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - Web Presentation

extension PresentationViewController {

    /// Mobile Safari user agent so responsive sites serve their phone breakpoint.
    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 " +
        "Mobile/15E148 Safari/604.1"

    /// Lazily creates and returns the external-display web view.
    func ensureWebView() -> WKWebView {
        if let webView = webView { return webView }

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = Self.mobileUserAgent
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.bounces = false
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        // Non-interactive on the TV; the phone remote drives scrolling.
        view.isUserInteractionEnabled = false

        webContainer.addSubview(view)
        webView = view
        return view
    }

    /// Loads `url` into the external web view and applies portrait/scale layout.
    func showWeb(url: URL) {
        hideCamera()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()

        webContainer.isHidden = false
        let view = ensureWebView()
        applyWebLayout()

        if view.url != url {
            view.load(URLRequest(url: url))
        }
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
        webContainer.isHidden = true
    }

    /// Applies scale-up + portrait rotation from `ExternalOutputSettings`.
    func applyWebLayout() {
        guard !webContainer.isHidden, let webView = webView else { return }

        let screenSize = webContainer.bounds.size
        guard screenSize.width > 0, screenSize.height > 0 else { return }

        let contentSize: CGSize
        if ExternalOutputSettings.orientation == .portrait {
            contentSize = CGSize(width: screenSize.height, height: screenSize.width)
        } else {
            contentSize = screenSize
        }

        let logicalWidth = ExternalOutputSettings.webTextSize.logicalWidth
        let scale = contentSize.width / logicalWidth
        applyRotatedLayout(to: webView, in: webContainer, scale: scale)
    }

    /// Scrolls the page by `delta` points in the web view's logical coordinate space.
    func scrollWeb(by delta: CGPoint) {
        guard let webView = webView, !webContainer.isHidden else { return }
        let script = "window.scrollBy(\(delta.x), \(delta.y));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Reloads the current page.
    func reloadWeb() {
        webView?.reload()
    }

    /// Scrolls the page to the top.
    func scrollWebToTop() {
        webView?.evaluateJavaScript("window.scrollTo(0, 0);", completionHandler: nil)
    }
}
