//
//  HomeHeaderNavTabsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct HomeHeaderNavLayoutTests {

    @Test func tabsOnlyOnRegularWidthAndHeight() {
        #expect(
            HomeHeaderNavLayout.showsDestinationTabs(
                horizontalSizeClass: .regular, verticalSizeClass: .regular
            )
        )
        #expect(
            !HomeHeaderNavLayout.showsDestinationTabs(
                horizontalSizeClass: .regular, verticalSizeClass: .compact
            )
        )
        #expect(
            !HomeHeaderNavLayout.showsDestinationTabs(
                horizontalSizeClass: .compact, verticalSizeClass: .regular
            )
        )
        #expect(
            !HomeHeaderNavLayout.showsDestinationTabs(
                horizontalSizeClass: .compact, verticalSizeClass: .compact
            )
        )
    }
}

@MainActor
struct HomeHeaderNavTabsTests {

    @Test func homeStartsSelected() {
        let tabs = HomeHeaderNavTabs()
        let home = tabButton(HomeHeaderDestination.home, in: tabs)
        let show = tabButton(HomeHeaderDestination.show, in: tabs)
        #expect(home?.accessibilityTraits.contains(.selected) == true)
        #expect(show?.accessibilityTraits.contains(.selected) != true)
        #expect(show?.configuration?.title == "Show")
        #expect(tabButton(HomeHeaderDestination.music, in: tabs) == nil)
    }

    @Test func showModeSelectsShowAndUsesShowName() {
        let tabs = HomeHeaderNavTabs()
        tabs.apply(
            HomeHeaderNavSelection(
                isShowMode: true,
                isMusicPinned: false,
                showTitle: "Spring Recital"
            )
        )
        let home = tabButton(HomeHeaderDestination.home, in: tabs)
        let show = tabButton(HomeHeaderDestination.show, in: tabs)
        #expect(home?.accessibilityTraits.contains(.selected) != true)
        #expect(show?.accessibilityTraits.contains(.selected) == true)
        #expect(show?.configuration?.title == "Spring Recital")
    }

    @Test func libraryIsNeverSelected() {
        let tabs = HomeHeaderNavTabs()
        tabs.apply(
            HomeHeaderNavSelection(
                isShowMode: true,
                isMusicPinned: true,
                showTitle: "Show"
            )
        )
        let library = tabButton(HomeHeaderDestination.library, in: tabs)
        #expect(library?.accessibilityTraits.contains(.selected) != true)
    }

    @Test func tapsReportTabBarDestinationsOnly() {
        let tabs = HomeHeaderNavTabs()
        var tapped: [HomeHeaderDestination] = []
        tabs.onSelect = { tapped.append($0) }
        for destination in HomeHeaderDestination.tabBarCases {
            tabButton(destination, in: tabs)?.sendActions(for: .touchUpInside)
        }
        #expect(tapped == HomeHeaderDestination.tabBarCases)
        #expect(tabButton(HomeHeaderDestination.music, in: tabs) == nil)
    }
}

@MainActor
struct HomeHeaderBarDestinationTabTests {

    @Test func phoneKeepsDropdown() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.destinationTabsOverride = false
        #expect(!bar.showsDestinationTabs)
        #expect(isEffectivelyHidden(tabButton(.home, in: bar)))
        #expect(!isEffectivelyHidden(dropdownButton(in: bar)))
    }

    @Test func padRegularShowsTabsAndHidesDropdown() {
        let bar = configuredPadBar()
        #expect(bar.showsDestinationTabs)
        #expect(!isEffectivelyHidden(tabButton(.home, in: bar)))
        #expect(tabButton(.music, in: bar) == nil)
        #expect(isEffectivelyHidden(dropdownButton(in: bar)))
    }

    @Test func padRegularHidesBackBecauseHomeTabReturns() {
        let bar = configuredPadBar()
        bar.setShowModeChrome(true)
        #expect(homeBackButton(in: bar)?.isHidden != false)
    }

    @Test func padRegularShowsSettingsOnHome() {
        let bar = configuredPadBar()
        bar.setShowModeChrome(false)
        let settings = settingsButton(in: bar)
        #expect(settings?.isHidden == false)
    }

    @Test func phoneHidesSettingsOnHome() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.destinationTabsOverride = false
        bar.setShowModeChrome(false)
        #expect(settingsButton(in: bar)?.isHidden != false)
    }

    @Test func tabTapCallsOnSelectDestination() {
        let bar = configuredPadBar()
        var destination: HomeHeaderDestination?
        bar.onSelectDestination = { destination = $0 }
        tabButton(.library, in: bar)?.sendActions(for: .touchUpInside)
        #expect(destination == .library)
    }
}

@MainActor
private func configuredPadBar() -> HomeHeaderBar {
    let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 1024, height: 52))
    bar.destinationTabsOverride = true
    return bar
}

@MainActor
private func tabButton(
    _ destination: HomeHeaderDestination,
    in root: UIView
) -> UIButton? {
    firstButton(in: root, identifier: destination.accessibilityIdentifier)
}

@MainActor
private func dropdownButton(in root: UIView) -> UIButton? {
    firstButton(in: root) { button in
        button.accessibilityLabel?.hasSuffix("menu") == true
    }
}

@MainActor
private func settingsButton(in root: UIView) -> UIButton? {
    firstButton(in: root) { $0.accessibilityLabel == "Settings" }
}

@MainActor
private func homeBackButton(in root: UIView) -> UIButton? {
    firstButton(in: root) { $0.accessibilityLabel == "Back" }
}

@MainActor
private func firstButton(
    in root: UIView,
    identifier: String
) -> UIButton? {
    firstButton(in: root) { $0.accessibilityIdentifier == identifier }
}

@MainActor
private func firstButton(
    in root: UIView,
    matching: (UIButton) -> Bool
) -> UIButton? {
    if let button = root as? UIButton, matching(button) {
        return button
    }
    for subview in root.subviews {
        if let found = firstButton(in: subview, matching: matching) {
            return found
        }
    }
    return nil
}

@MainActor
private func isEffectivelyHidden(_ view: UIView?) -> Bool {
    guard var current = view else { return true }
    while true {
        if current.isHidden { return true }
        guard let parent = current.superview else { return false }
        current = parent
    }
}
