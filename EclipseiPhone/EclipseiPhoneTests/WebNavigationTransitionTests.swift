//
//  WebNavigationTransitionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Phone-browser navigation must land on the TV even when it happens while the
/// bookmark is still being brought in by a content transition.
@MainActor
struct WebNavigationTransitionTests {

    private let bookmark = URL(string: "https://example.com/")!
    private let navigated = URL(string: "https://example.com/about")!

    @Test func navigationDuringIncomingTransitionRetargetsIt() {
        let vc = PresentationViewController()
        _ = vc.view
        vc.show(.web(bookmark))
        #expect(vc.isTransitionInFlight)
        let generation = vc.transitionGeneration

        vc.loadWeb(url: navigated)

        #expect(vc.isTransitionInFlight)
        #expect(vc.transitionGeneration == generation + 1)
        #expect(vc.pendingTransitionSource == .web(navigated))
        // The half-loaded incoming view is not promoted early with a wrong label.
        #expect(vc.webView == nil)
        #expect(vc.webRequestedURL == nil)
    }

    @Test func sameURLDuringIncomingTransitionIsNoOp() {
        let vc = PresentationViewController()
        _ = vc.view
        vc.show(.web(bookmark))
        let generation = vc.transitionGeneration

        vc.loadWeb(url: bookmark)

        #expect(vc.transitionGeneration == generation)
        #expect(vc.pendingTransitionSource == .web(bookmark))
    }

    @Test func navigationAfterCommitLoadsPrimaryInPlace() {
        let vc = PresentationViewController()
        _ = vc.view
        vc.applyShowDirect(.web(bookmark))
        let primary = vc.webView
        #expect(primary != nil)
        #expect(vc.webRequestedURL == bookmark)

        vc.loadWeb(url: navigated)

        #expect(vc.webView === primary)
        #expect(vc.webRequestedURL == navigated)
        #expect(vc.isTransitionInFlight == false)
    }

    @Test func commitAdoptsIncomingViewLoadedWithNavigatedURL() throws {
        let vc = PresentationViewController()
        _ = vc.view
        vc.show(.web(bookmark))
        vc.loadWeb(url: navigated)
        let incoming = try #require(vc.incomingWebView)
        let pending = try #require(vc.pendingTransitionSource)

        // Mirrors the commit step of the reveal (Cut/Crossfade both end here).
        vc.applyShowDirect(pending)

        #expect(vc.webView === incoming)
        #expect(vc.webRequestedURL == navigated)
        #expect(vc.presentedSource == .web(navigated))
    }
}
