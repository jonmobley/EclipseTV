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

@MainActor
struct HomeHeaderBarBackButtonTests {

    @Test func backHiddenOnHome() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(false)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }

    @Test func backShownInShowMode() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        let button = homeBackButton(in: bar)
        #expect(button?.isHidden == false)
        #expect(button?.isEnabled == true)
    }

    @Test func backHiddenAgainAfterLeavingShowMode() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setShowModeChrome(false)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }

    @Test func backTapCallsOnGoBack() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        var didGoBack = false
        bar.onGoBack = { didGoBack = true }
        let button = homeBackButton(in: bar)
        #expect(button != nil)
        button?.sendActions(for: .touchUpInside)
        #expect(didGoBack)
    }

    @Test func backHiddenWhileArranging() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setArranging(true)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }
}

@MainActor
private func homeBackButton(in root: UIView) -> UIButton? {
    if let button = root as? UIButton, button.accessibilityLabel == "Back" {
        return button
    }
    for subview in root.subviews {
        if let found = homeBackButton(in: subview) { return found }
    }
    return nil
}
