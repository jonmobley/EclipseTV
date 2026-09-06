//
//  PresentationViewController+WebVideo.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

// MARK: - Web Video Embed Presentation

extension PresentationViewController: WKScriptMessageHandler {

    /// Shows a YouTube / Vimeo embed edge-to-edge on the external web surface.
    func showWebVideo(_ link: WebVideoLink) {
        hideCamera()
        hidePDF()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()

        // Bookmark web views lack the embed message handler — rebuild.
        if webVideoLink == nil, webView != nil {
            teardownWebKeepingContainerVisible()
        }

        webContainer.isHidden = false
        if let adoptURL = link.embedURL ?? link.shellBaseURL {
            adoptIncomingWebView(loadedWith: adoptURL)
        }
        webVideoLink = link
        let view = ensureWebVideoView()
        applyWebLayout()

        guard let html = WebVideoShellHTML.document(for: link),
              let base = link.shellBaseURL else { return }
        webRequestedURL = link.embedURL ?? base
        webVideoPlaybackState = PlaybackState()
        view.loadHTMLString(html, baseURL: base)
        configureAudioSession(muted: false)
    }

    /// Tears down web-video state (also invoked from `teardownWeb`).
    func teardownWebVideo() {
        webVideoLink = nil
        webVideoPlaybackState = PlaybackState()
    }

    /// Play/pause the live embed. Returns false when no embed is showing.
    @discardableResult
    func toggleWebVideoPlayback() -> Bool {
        guard webVideoLink != nil, let webView, !webContainer.isHidden else {
            return false
        }
        let js = webVideoPlaybackState.isPlaying
            ? WebVideoPlayerBridge.pauseJavaScript
            : WebVideoPlayerBridge.playJavaScript
        webView.evaluateJavaScript(js, completionHandler: nil)
        return true
    }

    /// Relative skip on the live embed.
    @discardableResult
    func skipWebVideo(by delta: TimeInterval) -> Bool {
        guard webVideoLink != nil else { return false }
        let target = AirPlayVideoTransport.clampedTime(
            webVideoPlaybackState.currentTime + delta,
            duration: webVideoPlaybackState.duration
        )
        return seekWebVideo(to: target)
    }

    /// Absolute seek on the live embed.
    @discardableResult
    func seekWebVideo(to position: TimeInterval) -> Bool {
        guard webVideoLink != nil, let webView, !webContainer.isHidden else {
            return false
        }
        let target = AirPlayVideoTransport.clampedTime(
            position, duration: webVideoPlaybackState.duration
        )
        webView.evaluateJavaScript(
            WebVideoPlayerBridge.seekJavaScript(to: target),
            completionHandler: nil
        )
        return true
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == WebVideoPlayerBridge.messageName,
              let event = WebVideoPlayerBridge.Event(messageBody: message.body)
        else { return }

        webVideoPlaybackState = event.playbackState
        if event.action == "play"
            || (event.action == "timeupdate" && !event.paused) {
            configureAudioSession(muted: event.muted)
            AudioAmbientPolicy.applyYieldIfNeeded(
                forWebVideoPlaying: !event.paused, muted: event.muted
            )
        }
        NotificationCenter.default.post(
            name: ExternalDisplayManager.videoPlaybackDidChangeNotification,
            object: ExternalDisplayManager.shared
        )
    }

    // MARK: - Private

    /// Web view configured with the embed player message handler.
    private func ensureWebVideoView() -> WKWebView {
        if let webView, webVideoLink != nil { return webView }

        let config = EclipseWebKit.makeConfiguration()
        let proxy = WeakScriptMessageHandler(delegate: self)
        config.userContentController.add(
            proxy, name: WebVideoPlayerBridge.messageName
        )

        let view = WKWebView(frame: .zero, configuration: config)
        EclipseWebKit.applyDesktopSite(to: view)
        view.navigationDelegate = self
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.isUserInteractionEnabled = false

        webContainer.addSubview(view)
        webView = view
        webBackgroundTint = nil
        return view
    }
}
