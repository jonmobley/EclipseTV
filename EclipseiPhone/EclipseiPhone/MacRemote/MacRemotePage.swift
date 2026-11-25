//
//  MacRemotePage.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - MacRemotePage

/// Rules for showing Eclipse-for-Mac's own remote page inside the app.
///
/// The Mac serves one remote (`EclipsePro/RemoteControl/WebRemote`); the app
/// shows that same page instead of a second, hand-copied screen, so a browser
/// and the app can never drift apart.
///
/// Thread Safety: Stateless; safe to call from any thread.
enum MacRemotePage {

    /// Name the page's script uses to reach the app (`window.webkit.messageHandlers`).
    static let messageHandlerName = "eclipseApp"

    /// Messages the injected script posts to the app.
    enum Message: String {
        /// The Back arrow was added to the page's own header.
        case headerReady = "header-ready"
        /// The page has no header we recognise; the app shows its own Close button.
        case headerMissing = "header-missing"
        /// The Back arrow was tapped.
        case close
        /// The page's PIN card came up; it covers the header and its Back arrow.
        case pinShown = "pin-shown"
        /// The PIN card went away.
        case pinHidden = "pin-hidden"
    }

    /// Address to load for a parsed connect link.
    ///
    /// The one-time link secret rides in the `#t=` fragment, which the page reads
    /// and scrubs, and which is never sent to the Mac as part of the request.
    /// Without a secret the page asks for the PIN itself.
    static func url(for info: RemoteConnectInfo) -> URL? {
        guard var components = URLComponents(
            url: info.baseURL, resolvingAgainstBaseURL: false
        ) else { return nil }
        components.path = "/"
        components.query = nil
        components.fragment = info.bootstrapToken.map { "t=\($0)" }
        return components.url
    }

    /// Whether the page may go to `url`: only the Mac it was opened on.
    ///
    /// The remote never links anywhere else, so anything off that Mac (a
    /// redirect, a planted link) is refused instead of loading inside the app
    /// with the remote's sign-in still attached.
    static func allowsNavigation(to url: URL?, base: URL) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" { return true }
        return scheme == base.scheme?.lowercased()
            && url.host?.lowercased() == base.host?.lowercased()
            && effectivePort(url) == effectivePort(base)
    }

    /// Adds a Back arrow to the page's header, where the Show screen has one.
    ///
    /// Uses the page's own `head-btn` look. If the Mac's page ever changes shape
    /// the script says so and the app falls back to its own Back button, so
    /// there is always a way out. The page's PIN card covers its header, so the
    /// script also says when that card is up and the app's button stands in.
    static let backArrowScript = """
    (function () {
      var app = window.webkit && window.webkit.messageHandlers
        && window.webkit.messageHandlers.\(messageHandlerName);
      if (!app) return;
      var lead = document.querySelector(".topbar-lead");
      if (!lead) { app.postMessage("\(Message.headerMissing.rawValue)"); return; }
      var back = document.createElement("button");
      back.type = "button";
      back.className = "head-btn";
      back.setAttribute("aria-label", "Back");
      back.style.marginLeft = "-8px";
      back.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">'
        + '<path d="M15 4.5L7.5 12l7.5 7.5" fill="none" stroke="currentColor" '
        + 'stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      back.addEventListener("click", function () {
        app.postMessage("\(Message.close.rawValue)");
      });
      lead.insertBefore(back, lead.firstChild);
      app.postMessage("\(Message.headerReady.rawValue)");
      var pin = document.getElementById("pairOverlay");
      if (!pin) return;
      var tellPin = function () {
        app.postMessage(pin.hidden
          ? "\(Message.pinHidden.rawValue)" : "\(Message.pinShown.rawValue)");
      };
      new MutationObserver(tellPin).observe(
        pin, { attributes: true, attributeFilter: ["hidden"] }
      );
      tellPin();
    })();
    """

    // MARK: - Private Helpers

    private static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}
