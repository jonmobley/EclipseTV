//
//  HomeHeaderBarPracticeChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Practice Mode is always on (2026-11-25): every open Show offers Lock and
/// Blackout, connected or not, and Home never does.
@MainActor
struct HomeHeaderBarPracticeChromeTests {

    @Test func lockAndBlackoutShowInAShowWithNothingConnected() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.paused)
        #expect(bar.showsLiveOutputChrome == true)
    }

    @Test func lockAndBlackoutShowWhenAirPlayConnects() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setPresenting(true)
        bar.setConnectionState(.paused)
        #expect(bar.showsLiveOutputChrome == true)
    }

    @Test func lockAndBlackoutShowWhenEclipseTVIsLinked() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.connected)
        #expect(bar.showsLiveOutputChrome == true)
    }

    @Test func lockAndBlackoutHiddenOnHome() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(false)
        bar.setPresenting(true)
        bar.setConnectionState(.connected)
        #expect(bar.showsLiveOutputChrome == false)
    }

    @Test func lockAndBlackoutGoAwayWhenLeavingTheShow() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setShowModeChrome(false)
        #expect(bar.showsLiveOutputChrome == false)
    }
}

@MainActor
struct HomeHeaderBarBackButtonTests {

    @Test func backHiddenOnHome() {
        let bar = dropdownHeaderBar()
        bar.setShowModeChrome(false)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }

    @Test func backShownInShowMode() {
        let bar = dropdownHeaderBar()
        bar.setShowModeChrome(true)
        let button = homeBackButton(in: bar)
        #expect(button?.isHidden == false)
        #expect(button?.isEnabled == true)
    }

    @Test func backHiddenAgainAfterLeavingShowMode() {
        let bar = dropdownHeaderBar()
        bar.setShowModeChrome(true)
        bar.setShowModeChrome(false)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }

    @Test func backTapCallsOnGoBack() {
        let bar = dropdownHeaderBar()
        bar.setShowModeChrome(true)
        var didGoBack = false
        bar.onGoBack = { didGoBack = true }
        let button = homeBackButton(in: bar)
        #expect(button != nil)
        button?.sendActions(for: .touchUpInside)
        #expect(didGoBack)
    }

    @Test func backHiddenWhileArranging() {
        let bar = dropdownHeaderBar()
        bar.setShowModeChrome(true)
        bar.setArranging(true)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }
}

/// The chevron belongs to the dropdown header. Pinned so these tests mean the
/// same thing on an iPad simulator, where the tabbed header hides it on purpose
/// (`padRegularHidesBackBecauseHomeTabReturns` covers that side).
@MainActor
private func dropdownHeaderBar() -> HomeHeaderBar {
    let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
    bar.destinationTabsOverride = false
    return bar
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
