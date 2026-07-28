//
//  EclipseWebKit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import WebKit

/// Shared WKWebView setup so cookies / localStorage persist across browser sessions.
enum EclipseWebKit {

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
}
