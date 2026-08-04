//
//  WebBackgroundTint.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

/// Keeps a web view's overscroll backdrop on the page's own background colour.
///
/// Pulling past the top or bottom of a page reveals `WKWebView.backgroundColor` /
/// `scrollView.backgroundColor`. Those were hard-coded black, so a white site
/// flashed a black gutter. This reads WebKit's `underPageBackgroundColor` (derived
/// from the document) and paints only those two layers — never the HTML, and never
/// by writing `underPageBackgroundColor` (that would freeze WebKit's auto tracking).
///
/// Thread safety: main-actor only.
@MainActor
final class WebBackgroundTint {

    /// Backdrop used until a page reports a usable colour.
    static let fallback = UIColor.black

    /// Latest resolved colour.
    private(set) var color: UIColor = WebBackgroundTint.fallback

    private weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    /// Starts following `webView` and paints the backdrop it is already showing.
    ///
    /// - Parameter webView: Web view to follow. Held weakly; the caller owns it.
    init(webView: WKWebView) {
        self.webView = webView

        // URL is observed too: two pages that share a background colour produce no
        // `underPageBackgroundColor` change, and a blank start page must re-resolve
        // once it becomes a real site.
        observations = [
            webView.observe(\.underPageBackgroundColor, options: [.initial, .new]) {
                [weak self] web, _ in
                MainActor.assumeIsolated { self?.update(from: web) }
            },
            webView.observe(\.url, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.update(from: web) }
            }
        ]
    }

    /// Re-reads the page colour, e.g. once a navigation has settled.
    func refresh() {
        guard let webView else { return }
        update(from: webView)
    }

    // MARK: - Private Helpers

    private func update(from web: WKWebView) {
        let resolved = Self.resolve(web.underPageBackgroundColor)
        guard resolved != color else { return }
        color = resolved
        Self.applyBackdrop(resolved, to: web)
    }

    /// Paints the layers visible when the user overscrolls — not the document.
    private static func applyBackdrop(_ color: UIColor, to web: WKWebView) {
        web.backgroundColor = color
        web.scrollView.backgroundColor = color
    }

    /// Maps WebKit's report to an opaque backdrop, or `fallback` when unusable.
    private static func resolve(_ reported: UIColor?) -> UIColor {
        guard let reported else { return fallback }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard reported.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              alpha > 0.99
        else {
            return fallback
        }
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
