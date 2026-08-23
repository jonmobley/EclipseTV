//
//  BrowserSessionBackRootTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Opening-load redirects used to append after the first capture, so Back walked
//  hops the user never asked for. Recapture until the user navigates.
//

import Testing
@testable import EclipseiPhone

struct BrowserSessionBackRootTests {

    @Test func backStaysPutAfterRedirectsSettle() {
        var root = BrowserSessionBackRoot()
        root.captureOpeningLoad(backListCount: 0)
        root.captureOpeningLoad(backListCount: 1)
        #expect(!root.shouldGoBack(backListCount: 1))
    }

    @Test func backWalksPagesTheUserOpened() {
        var root = BrowserSessionBackRoot()
        root.captureOpeningLoad(backListCount: 1)
        root.markUserNavigated()
        root.captureOpeningLoad(backListCount: 2)
        #expect(root.shouldGoBack(backListCount: 2))
        #expect(!root.shouldGoBack(backListCount: 1))
    }

    @Test func uncapturedBackDoesNotGoBack() {
        let root = BrowserSessionBackRoot()
        #expect(!root.shouldGoBack(backListCount: 2))
    }
}
