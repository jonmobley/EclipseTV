//
//  BrowserSessionBackRoot.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import WebKit

/// How deep WKWebView history was after the opening load’s redirects.
///
/// Warm loads often leave extra back-forward entries (`http`→`https`, trailing
/// slash). Capturing once on the first non-blank URL is too early: later
/// redirects still append, so Back would walk hops the user never asked for.
/// The root is recaptured until the user actually navigates.
struct BrowserSessionBackRoot {

    /// `backList.count` at the current opening-load snapshot.
    private(set) var count = 0
    /// True once `count` has been recorded at least once.
    private(set) var didCapture = false
    /// True after a user-initiated main-frame navigation.
    private(set) var userHasNavigated = false

    /// Updates the root from the current back-forward list during the opening load.
    mutating func captureOpeningLoad(backListCount: Int) {
        guard !userHasNavigated else { return }
        count = backListCount
        didCapture = true
    }

    /// Freezes the root so later loads are real Back history.
    mutating func markUserNavigated() {
        userHasNavigated = true
    }

    /// Whether Back has in-session history and should `goBack()`.
    func shouldGoBack(backListCount: Int) -> Bool {
        let root = didCapture ? count : backListCount
        return backListCount > root
    }

    /// True for taps/forms in the main frame — not redirects, reloads, or iframes.
    static func isUserMainFrameNavigation(_ action: WKNavigationAction) -> Bool {
        if let frame = action.targetFrame, !frame.isMainFrame { return false }
        switch action.navigationType {
        case .linkActivated, .formSubmitted, .formResubmitted:
            return true
        default:
            return false
        }
    }
}
