//
//  SlideshowRibbonChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct SlideshowRibbonChromeTests {

    @Test func firstRibbonChromeRebuildsShowLayout() {
        let next = LibraryGridViewController.SlideshowRibbonChrome(
            inGrid: false, docked: true
        )
        #expect(
            LibraryGridViewController.SlideshowRibbonChrome.needsLayoutRebuild(
                from: nil, to: next
            )
        )
    }

    @Test func slideAdvanceDoesNotRebuildShowLayout() {
        let chrome = LibraryGridViewController.SlideshowRibbonChrome(
            inGrid: false, docked: true
        )
        #expect(
            LibraryGridViewController.SlideshowRibbonChrome.needsLayoutRebuild(
                from: chrome, to: chrome
            ) == false
        )
    }

    @Test func ribbonAppearingRebuildsShowLayout() {
        let previous = LibraryGridViewController.SlideshowRibbonChrome(
            inGrid: false, docked: false
        )
        let next = LibraryGridViewController.SlideshowRibbonChrome(
            inGrid: false, docked: true
        )
        #expect(
            LibraryGridViewController.SlideshowRibbonChrome.needsLayoutRebuild(
                from: previous, to: next
            )
        )
    }

    @Test func hidingTheRibbonRebuildsShowLayout() {
        let previous = LibraryGridViewController.SlideshowRibbonChrome(
            inGrid: false, docked: true
        )
        let next = LibraryGridViewController.SlideshowRibbonChrome(
            inGrid: false, docked: false
        )
        #expect(
            LibraryGridViewController.SlideshowRibbonChrome.needsLayoutRebuild(
                from: previous, to: next
            )
        )
    }

    @Test func ribbonAppearingUnderAnOnScreenHeroAnimates() {
        let previous = LiveChromeState(heroVisible: true, ribbonDocked: false)
        let next = LiveChromeState(heroVisible: true, ribbonDocked: true)
        #expect(LiveChromeState.animatesRibbonTransition(from: previous, to: next))
    }

    @Test func ribbonHidingUnderAnOnScreenHeroAnimates() {
        let previous = LiveChromeState(heroVisible: true, ribbonDocked: true)
        let next = LiveChromeState(heroVisible: true, ribbonDocked: false)
        #expect(LiveChromeState.animatesRibbonTransition(from: previous, to: next))
    }

    @Test func firstChromePassNeverAnimatesTheRibbon() {
        let next = LiveChromeState(heroVisible: true, ribbonDocked: true)
        #expect(LiveChromeState.animatesRibbonTransition(from: nil, to: next) == false)
    }

    @Test func ribbonArrivingWithTheHeroDoesNotAnimate() {
        let previous = LiveChromeState(heroVisible: false, ribbonDocked: false)
        let next = LiveChromeState(heroVisible: true, ribbonDocked: true)
        #expect(
            LiveChromeState.animatesRibbonTransition(from: previous, to: next) == false
        )
    }

    @Test func ribbonLeavingWithTheHeroDoesNotAnimate() {
        let previous = LiveChromeState(heroVisible: true, ribbonDocked: true)
        let next = LiveChromeState(heroVisible: false, ribbonDocked: false)
        #expect(
            LiveChromeState.animatesRibbonTransition(from: previous, to: next) == false
        )
    }

    @Test func unchangedRibbonDoesNotAnimate() {
        let chrome = LiveChromeState(heroVisible: true, ribbonDocked: true)
        #expect(
            LiveChromeState.animatesRibbonTransition(from: chrome, to: chrome) == false
        )
    }

    @Test func phonePortraitStaysStacked() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: true,
                verticalSizeClass: .regular,
                horizontalSizeClass: .compact,
                bounds: CGSize(width: 390, height: 844)
            ) == false
        )
        #expect(
            LibraryGridViewController.usesVerticalDockedRibbon(
                isSideBySide: false,
                horizontalSizeClass: .compact
            ) == false
        )
    }

    @Test func phoneLandscapeUsesHorizontalSideBySide() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: true,
                verticalSizeClass: .compact,
                horizontalSizeClass: .compact,
                bounds: CGSize(width: 844, height: 390)
            )
        )
        #expect(
            LibraryGridViewController.usesVerticalDockedRibbon(
                isSideBySide: true,
                horizontalSizeClass: .compact
            ) == false
        )
    }

    /// Bounds can flip before `verticalSizeClass` during a turn. Keep the
    /// left-aligned preview rather than staying stacked and centered.
    @Test func phoneLandscapeBoundsWinWhenPortraitTraitsLag() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: true,
                verticalSizeClass: .regular,
                horizontalSizeClass: .compact,
                bounds: CGSize(width: 844, height: 390)
            )
        )
    }

    /// Plus/Max landscape is `.regular` width; the preview still uses phone
    /// sizing (0.46 cap) so it stays a leading column, not an iPad pane.
    @Test func phoneLandscapeHeroStaysALeadingColumn() {
        let size = LibraryGridViewController.sideBySideHeroSize(
            availableWidth: 780,
            availableHeight: 260,
            aspect: 16.0 / 9.0,
            horizontalSizeClass: .compact,
            containerWidth: 844
        )
        #expect(size.width >= 120)
        #expect(size.height >= 68)
        #expect(size.width <= 844 * 0.46 + 0.5)
        #expect(size.width < 780 - LibraryGridViewController.sideBySideMinGridWidth)
    }

    @Test func iPadPortraitStaysStacked() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: true,
                verticalSizeClass: .regular,
                horizontalSizeClass: .regular,
                bounds: CGSize(width: 1024, height: 1366)
            ) == false
        )
    }

    @Test func iPadLandscapeKeepsRibbonUnderThePreview() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: true,
                verticalSizeClass: .regular,
                horizontalSizeClass: .regular,
                bounds: CGSize(width: 1366, height: 1024)
            )
        )
        #expect(
            LibraryGridViewController.usesVerticalDockedRibbon(
                isSideBySide: true,
                horizontalSizeClass: .regular
            ) == false
        )
    }

    @Test func tallRegularSplitPaneStaysStacked() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: true,
                verticalSizeClass: .regular,
                horizontalSizeClass: .regular,
                bounds: CGSize(width: 700, height: 1024)
            ) == false
        )
    }

    @Test func noLiveHeroNeverGoesSideBySide() {
        #expect(
            LibraryGridViewController.prefersSideBySideChrome(
                showsLiveHero: false,
                verticalSizeClass: .compact,
                horizontalSizeClass: .regular,
                bounds: CGSize(width: 1366, height: 1024)
            ) == false
        )
    }

    @Test func regularWidthSideBySideHeroLeavesAUsableGrid() {
        let availableWidth: CGFloat = 1200
        let availableHeight: CGFloat = 700
        let aspect: CGFloat = 16.0 / 9.0
        let phone = LibraryGridViewController.sideBySideHeroSize(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            aspect: aspect,
            horizontalSizeClass: .compact,
            containerWidth: 1366
        )
        let tablet = LibraryGridViewController.sideBySideHeroSize(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            aspect: aspect,
            horizontalSizeClass: .regular,
            containerWidth: 1366
        )
        #expect(tablet.width > phone.width)
        #expect(tablet.width <= 1366 * 0.58 + 0.5)
        #expect(
            availableWidth - tablet.width
                >= LibraryGridViewController.sideBySideRegularMinGridWidth - 0.5
        )
    }

    @Test func liveRibbonNeverUsesVerticalStrip() {
        #expect(
            LibraryGridViewController.usesVerticalDockedRibbon(
                isSideBySide: true,
                horizontalSizeClass: .regular
            ) == false
        )
        #expect(
            LibraryGridViewController.usesVerticalDockedRibbon(
                isSideBySide: true,
                horizontalSizeClass: .compact
            ) == false
        )
        #expect(
            LibraryGridViewController.usesVerticalDockedRibbon(
                isSideBySide: false,
                horizontalSizeClass: .regular
            ) == false
        )
    }

    @Test func verticalRevealScrollsOffscreenItems() {
        let item = CGRect(x: 0, y: 400, width: 80, height: 45)
        let offset = LibraryGridViewController.dockedRibbonRevealOffset(
            itemFrame: item,
            bounds: CGRect(x: 0, y: 0, width: 80, height: 200),
            contentSize: CGSize(width: 80, height: 600),
            contentOffset: .zero,
            adjustedContentInset: .zero,
            scrollsVertically: true
        )
        #expect(offset != nil)
        #expect(offset?.y == 245)
    }

    @Test func dockedRibbonHeightAddsBottomPadding() {
        let padding = LibraryGridViewController.slideshowRibbonBottomPadding
        #expect(padding > 0)
        #expect(
            LibraryGridViewController.dockedSlideshowRibbonHeight(thumbHeight: 80)
            == 80 + padding
        )
    }

    @Test func heroCardKeepsItsBlackBandWithNoRibbon() {
        #expect(
            LibraryGridViewController.liveChromeBottomPadding(
                heroBottomPadding: 16, ribbonDocked: false
            ) == 16
        )
    }

    @Test func dockedRibbonDoesNotStackASecondBlackBand() {
        #expect(
            LibraryGridViewController.liveChromeBottomPadding(
                heroBottomPadding: 16, ribbonDocked: true
            ) == 0
        )
    }

    @Test func verticalRevealLeavesVisibleItemsAlone() {
        let item = CGRect(x: 0, y: 40, width: 80, height: 45)
        let offset = LibraryGridViewController.dockedRibbonRevealOffset(
            itemFrame: item,
            bounds: CGRect(x: 0, y: 0, width: 80, height: 200),
            contentSize: CGSize(width: 80, height: 600),
            contentOffset: .zero,
            adjustedContentInset: .zero,
            scrollsVertically: true
        )
        #expect(offset == nil)
    }
}
