//
//  HeroWebViewportSyncTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The hero website only moves the TV for the operator's own scrolls and pinches.
//

import Testing
@testable import EclipseiPhone

struct HeroWebViewportSyncTests {

    @Test func fingersGlideAndPinchCountAsOperatorMotion() {
        #expect(HeroWebViewportSync.isOperatorMotion(
            tracking: true, decelerating: false, zooming: false, zoomBouncing: false))
        #expect(HeroWebViewportSync.isOperatorMotion(
            tracking: false, decelerating: true, zooming: false, zoomBouncing: false))
        #expect(HeroWebViewportSync.isOperatorMotion(
            tracking: false, decelerating: false, zooming: true, zoomBouncing: false))
        #expect(HeroWebViewportSync.isOperatorMotion(
            tracking: false, decelerating: false, zooming: false, zoomBouncing: true))
    }

    @Test func heroRelayoutDoesNotMoveTheTV() {
        #expect(!HeroWebViewportSync.isOperatorMotion(
            tracking: false, decelerating: false, zooming: false, zoomBouncing: false))
    }
}
