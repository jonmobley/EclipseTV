//
//  WebViewportMirrorTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The TV follows the phone browser's zoom and position, and never shows a page
//  smaller than the screen.
//

import CoreGraphics
import WebKit
import UIKit
import Testing
@testable import EclipseiPhone

struct WebViewportMirrorTests {

    private let bounds = CGSize(width: 1280, height: 720)

    @Test func unzoomedPageMirrorsOnlyVerticalProgress() {
        let mirror = WebViewportMirror(
            zoomScale: 1,
            contentOffset: CGPoint(x: 0, y: 640),
            contentSize: CGSize(width: 1280, height: 2000),
            boundsSize: bounds
        )
        #expect(mirror.zoomScale == 1)
        #expect(mirror.progressX == 0)
        #expect(abs(mirror.progressY - 0.5) < 0.0001)
    }

    @Test func zoomedPageMirrorsBothAxes() {
        // Zoom 2: content doubles; scrolled to the right edge, a quarter down.
        let mirror = WebViewportMirror(
            zoomScale: 2,
            contentOffset: CGPoint(x: 1280, y: 820),
            contentSize: CGSize(width: 2560, height: 4000),
            boundsSize: bounds
        )
        #expect(mirror.zoomScale == 2)
        #expect(abs(mirror.progressX - 1) < 0.0001)
        #expect(abs(mirror.progressY - 0.25) < 0.0001)
    }

    @Test func pageShrunkBelowFitIsSentAtFit() {
        // Pinched to 0.5 on a normal-width page: the TV keeps the page full width.
        let mirror = WebViewportMirror(
            zoomScale: 0.5,
            contentOffset: .zero,
            contentSize: CGSize(width: 640, height: 1000),
            boundsSize: bounds
        )
        #expect(mirror.zoomScale == 1)
    }

    @Test func fitScaleIsOneForNormalPages() {
        #expect(WebViewportMirror.fitScale(zoomScale: 1, contentWidth: 1280, boundsWidth: 1280) == 1)
        #expect(WebViewportMirror.fitScale(zoomScale: 0.5, contentWidth: 640, boundsWidth: 1280) == 1)
    }

    @Test func fitScaleLetsAWidePageShowItsWholeWidth() {
        // Page laid out 2560 wide: fitting the card's width is zoom 0.5.
        let fit = WebViewportMirror.fitScale(zoomScale: 1, contentWidth: 2560, boundsWidth: 1280)
        #expect(abs(fit - 0.5) < 0.0001)
    }

    @Test func contentOffsetPlacesTheSamePartOnALargerPage() {
        let mirror = WebViewportMirror(zoomScale: 2, progressX: 0.5, progressY: 0.25)
        let offset = mirror.contentOffset(
            contentSize: CGSize(width: 3840, height: 8000),
            boundsSize: CGSize(width: 1920, height: 1080)
        )
        #expect(abs(offset.x - 960) < 0.0001)
        #expect(abs(offset.y - 1730) < 0.0001)
    }

    @Test func contentOffsetStaysInsideAShortPage() {
        let mirror = WebViewportMirror(zoomScale: 1, progressX: 3, progressY: -1)
        let offset = mirror.contentOffset(contentSize: CGSize(width: 1000, height: 500), boundsSize: bounds)
        #expect(offset == .zero)
    }
}

/// Real web pages: the phone's zoomed view lands on the TV's page, which
/// takes no touches, the same way the AirPlay page is set up (2026-11-23).
///
/// CI runs the suite in parallel, where a page load once never reported back and the
/// job hung for six hours (2026-11-27). So every way a load can end counts (finish,
/// failure, web process crash), a load that says nothing gives up after a while and is
/// tried again, and the suite has a time limit.
@MainActor
@Suite(.timeLimit(.minutes(10)))
struct WebViewportMirrorWebKitTests {

    /// Resumes once, with true only when the page finished loading.
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private var attempt = 0

        func wait(load: () -> Void) async -> Bool {
            attempt += 1
            let thisAttempt = attempt
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                load()
                // Dispatch, not a sleeping task: CI's task pool can be busy for minutes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
                    guard let self, self.attempt == thisAttempt else { return }
                    self.end(false)
                }
            }
        }

        private func end(_ loaded: Bool) {
            continuation?.resume(returning: loaded)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { end(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            end(false)
        }
        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) { end(false) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { end(false) }
    }

    private func loadedPage(width: CGFloat, height: CGFloat, interactive: Bool) async -> WKWebView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let web = WKWebView(frame: window.bounds, configuration: EclipseWebKit.makeConfiguration())
        web.isUserInteractionEnabled = interactive
        window.addSubview(web)
        window.isHidden = false
        let waiter = LoadWaiter()
        web.navigationDelegate = waiter
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0"><div style="height:4000px;background:linear-gradient(red,blue)"></div></body></html>
        """
        var loaded = false
        for _ in 0..<3 where !loaded {
            loaded = await waiter.wait { web.loadHTMLString(html, baseURL: nil) }
        }
        #expect(loaded, "test page never finished loading")
        // Let WebKit settle content size and zoom limits.
        for _ in 0..<20 where web.scrollView.contentSize.height < 3000 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        objc_setAssociatedObject(web, "waiter", waiter, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(web, "window", window, .OBJC_ASSOCIATION_RETAIN)
        return web
    }

    @Test func tvPageFollowsPhoneZoomAndPosition() async {
        let phone = await loadedPage(width: 640, height: 360, interactive: true)
        let tv = await loadedPage(width: 640, height: 360, interactive: false)
        let phoneScroll = phone.scrollView
        phoneScroll.maximumZoomScale = max(phoneScroll.maximumZoomScale, 3)
        phoneScroll.setZoomScale(2, animated: false)
        phoneScroll.contentOffset = CGPoint(
            x: (phoneScroll.contentSize.width - phoneScroll.bounds.width) / 2,
            y: (phoneScroll.contentSize.height - phoneScroll.bounds.height) / 4
        )
        let mirror = WebViewportMirror(
            zoomScale: phoneScroll.zoomScale,
            contentOffset: phoneScroll.contentOffset,
            contentSize: phoneScroll.contentSize,
            boundsSize: phoneScroll.bounds.size
        )
        #expect(abs(mirror.zoomScale - 2) < 0.01)

        mirror.apply(to: tv.scrollView)

        let tvScroll = tv.scrollView
        #expect(abs(tvScroll.zoomScale - 2) < 0.01)
        let tvMaxX = tvScroll.contentSize.width - tvScroll.bounds.width
        let tvMaxY = tvScroll.contentSize.height - tvScroll.bounds.height
        #expect(tvMaxX > 0)
        #expect(abs(tvScroll.contentOffset.x / tvMaxX - 0.5) < 0.02)
        #expect(abs(tvScroll.contentOffset.y / tvMaxY - 0.25) < 0.02)
    }

    @Test func phonePageShrunkSmallerThanFitIsSentAtFit() async {
        let phone = await loadedPage(width: 640, height: 360, interactive: true)
        let scroll = phone.scrollView
        scroll.minimumZoomScale = 0.25
        scroll.setZoomScale(0.5, animated: false)
        let mirror = WebViewportMirror(
            zoomScale: scroll.zoomScale,
            contentOffset: scroll.contentOffset,
            contentSize: scroll.contentSize,
            boundsSize: scroll.bounds.size
        )
        #expect(mirror.zoomScale == 1)
    }
}
