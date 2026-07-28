//
//  WebRemoteViewController+Popups.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - WKUIDelegate (OAuth / window.open)

extension WebRemoteViewController: WKUIDelegate {

    /// Presents a phone-only sheet for `window.open` / `target=_blank`.
    ///
    /// AirPlay is not updated; login UI stays on the phone. Session cookies
    /// flow back to the main page via the shared default data store.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        WebPopupViewController.present(from: self, configuration: configuration)
    }
}
