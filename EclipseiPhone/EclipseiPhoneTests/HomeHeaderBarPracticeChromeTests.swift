//
//  HomeHeaderBarPracticeChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct HomeHeaderBarPracticeChromeTests {

    @Test func lockAndBlackoutHiddenWhenDisconnectedAndPracticeOff() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setPreviewsWhenDisconnected(false)
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.paused)
        #expect(bar.showsLiveOutputChrome == false)
    }

    @Test func lockAndBlackoutShowWhenPracticeIsOn() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setPreviewsWhenDisconnected(true)
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.paused)
        #expect(bar.showsLiveOutputChrome == true)
    }

    @Test func lockAndBlackoutShowWhenAirPlayConnects() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setPreviewsWhenDisconnected(false)
        bar.setShowModeChrome(true)
        bar.setPresenting(true)
        bar.setConnectionState(.paused)
        #expect(bar.showsLiveOutputChrome == true)
    }

    @Test func lockAndBlackoutShowWhenEclipseTVIsLinked() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setPreviewsWhenDisconnected(false)
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.connected)
        #expect(bar.showsLiveOutputChrome == true)
    }

    @Test func lockAndBlackoutHiddenOnHomeEvenWithPracticeOn() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setPreviewsWhenDisconnected(true)
        bar.setShowModeChrome(false)
        bar.setPresenting(false)
        bar.setConnectionState(.paused)
        #expect(bar.showsLiveOutputChrome == false)
    }
}
