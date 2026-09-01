//
//  SlideshowRibbonChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
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
}
