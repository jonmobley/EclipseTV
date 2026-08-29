//
//  EclipseWebKit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import WebKit

/// Shared WKWebView setup so cookies / localStorage persist across browser sessions.
enum EclipseWebKit {

    /// Mac Safari UA. iPhone WKWebView defaults to mobile; iPad often already
    /// requests desktop, but a custom iPhone UA was forcing mobile on both.
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

    /// Persistent configuration: disk-backed cookies and site data via the default store.
    /// - Parameter mediaHandler: When set, injects the phone→AirPlay HTML5 media reporter.
    static func makeConfiguration(
        mediaHandler: WKScriptMessageHandler? = nil
    ) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Required for programmatic play() on the external (non-interactive) WebView.
        config.allowsPictureInPictureMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        if let mediaHandler {
            let proxy = WeakScriptMessageHandler(delegate: mediaHandler)
            config.userContentController.add(
                proxy, name: EclipseWebMediaSync.messageName
            )
            let script = WKUserScript(
                source: EclipseWebMediaSync.reporterJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }
        return config
    }

    /// Overrides the device UA so servers and client hints don't see iPhone.
    static func applyDesktopSite(to webView: WKWebView) {
        webView.customUserAgent = desktopUserAgent
    }
}
