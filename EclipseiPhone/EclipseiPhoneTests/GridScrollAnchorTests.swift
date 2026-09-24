//
//  GridScrollAnchorTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct GridScrollAnchorTests {

    /// The reported bug: bottom of a portrait grid, turn to landscape (shorter
    /// content), turn back. The bottom must still be the bottom in every range.
    @Test func bottomStaysTheBottomAcrossAShorterAndTallerRange() {
        let portrait = GridScrollAnchor(progress: 2400, maxProgress: 2400)
        #expect(portrait.fraction == 1)
        #expect(portrait.progress(forMaxProgress: 900) == 900)

        let landscape = GridScrollAnchor(progress: 900, maxProgress: 900)
        #expect(landscape.progress(forMaxProgress: 2400) == 2400)
    }

    @Test func topStaysTheTop() {
        let anchor = GridScrollAnchor(progress: 0, maxProgress: 2400)
        #expect(anchor.fraction == 0)
        #expect(anchor.progress(forMaxProgress: 900) == 0)
    }

    @Test func midScrollKeepsItsShareOfTheRange() {
        let anchor = GridScrollAnchor(progress: 600, maxProgress: 2400)
        #expect(anchor.fraction == 0.25)
        #expect(anchor.progress(forMaxProgress: 1000) == 250)
    }

    /// Captured mid-bounce past the end, the grid comes back flush to its last
    /// row, not stranded past it.
    @Test func overscrollPastTheEndClampsToTheBottom() {
        let anchor = GridScrollAnchor(progress: 2460, maxProgress: 2400)
        #expect(anchor.fraction == 1)
        #expect(anchor.progress(forMaxProgress: 900) == 900)
    }

    @Test func overscrollAboveTheTopClampsToTheTop() {
        let anchor = GridScrollAnchor(progress: -80, maxProgress: 2400)
        #expect(anchor.fraction == 0)
    }

    /// A range with nothing to scroll has no place to remember and no place to
    /// restore to.
    @Test func unscrollableRangesAreTreatedAsTheTop() {
        let anchor = GridScrollAnchor(progress: 120, maxProgress: 0)
        #expect(anchor.fraction == 0)

        let bottom = GridScrollAnchor(progress: 1, maxProgress: 1)
        #expect(bottom.progress(forMaxProgress: 0) == 0)
        #expect(bottom.progress(forMaxProgress: -40) == 0)
    }

    /// A note or ribbon under the preview grows the top inset. A scrolled grid
    /// keeps the offset it had, instead of shifting the thumbnails down.
    @Test func scrolledGridHoldsStillWhenLiveChromeGrows() {
        let offset = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -180,
            previousProgress: 220,
            adjustedTopInset: 490,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(offset == -180)
    }

    /// Same hold when the note or ribbon goes away: thumbnails must not jump up.
    @Test func scrolledGridHoldsStillWhenLiveChromeShrinks() {
        let offset = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -270,
            previousProgress: 220,
            adjustedTopInset: 400,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(offset == -270)
    }

    /// Already at the top, the first row moves down with the new chrome.
    @Test func gridAtTheTopMovesWithLiveChrome() {
        let grown = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -400,
            previousProgress: 0,
            adjustedTopInset: 490,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(grown == -490)

        let shrunk = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -490,
            previousProgress: 0,
            adjustedTopInset: 400,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(shrunk == -400)
    }

    /// A bounce past the top, or a fraction of a point, is still the top.
    @Test func nearTopStillMovesWithLiveChrome() {
        let bounced = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -430,
            previousProgress: -30,
            adjustedTopInset: 490,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(bounced == -490)

        let noise = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -399.6,
            previousProgress: 0.4,
            adjustedTopInset: 490,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(noise == -489.6)
    }

    /// Just past the slop counts as scrolled, so the thumbnails stay put.
    @Test func aRealScrollDoesNotMoveWithLiveChrome() {
        let offset = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -398,
            previousProgress: 2,
            adjustedTopInset: 490,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(offset == -398)
    }

    /// A bottom-inset change (mini player) still keeps the same content progress.
    @Test func bottomInsetChangeKeepsScrollProgress() {
        let offset = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -180,
            previousProgress: 220,
            adjustedTopInset: 400,
            maxScroll: 2000,
            topInsetChanged: false
        )
        #expect(offset == -180)
    }

    /// Shrinking the inset can leave a barely-scrolled offset above the new
    /// minimum. It clamps to the top of the new range rather than past it.
    @Test func heldOffsetClampsIntoTheNewRange() {
        let offset = LibraryGridViewController.heroOverlayContentOffsetY(
            previousOffsetY: -480,
            previousProgress: 20,
            adjustedTopInset: 400,
            maxScroll: 2000,
            topInsetChanged: true
        )
        #expect(offset == -400)
    }
}
