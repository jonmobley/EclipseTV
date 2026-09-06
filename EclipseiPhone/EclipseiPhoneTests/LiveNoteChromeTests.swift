//
//  LiveNoteChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct LiveNoteChromeTests {

    @Test func noteUnderTheBareHeroUsesTheFullGutter() {
        #expect(
            LibraryGridViewController.liveNoteTopGap(ribbonDocked: false)
                == LibraryGridViewController.sideBySideGutter
        )
    }

    /// The ribbon already pads its own bottom edge, so the card makes up only
    /// the difference and the spacing reads the same with or without a ribbon.
    @Test func noteUnderTheRibbonSubtractsTheStripPadding() {
        let gap = LibraryGridViewController.liveNoteTopGap(ribbonDocked: true)
        #expect(
            gap + LibraryGridViewController.slideshowRibbonBottomPadding
                == LibraryGridViewController.sideBySideGutter
        )
    }

    @Test func noteCardRestoresTheBlackBandUnderADockedRibbon() {
        #expect(
            LibraryGridViewController.liveChromeBottomPadding(
                heroBottomPadding: 16, ribbonDocked: true, noteDocked: true
            ) == 16
        )
    }

    @Test func noteCardKeepsTheBlackBandWithNoRibbon() {
        #expect(
            LibraryGridViewController.liveChromeBottomPadding(
                heroBottomPadding: 16, ribbonDocked: false, noteDocked: true
            ) == 16
        )
    }

    @Test func noteCardSizesItselfFromItsText() {
        let card = LiveNoteCardView()
        card.configure(note: "Cue the band")
        let short = card.height(forWidth: 320)
        card.configure(note: String(repeating: "Cue the band. ", count: 12))
        let long = card.height(forWidth: 320)
        #expect(short > 0)
        #expect(long > short)
    }

    /// A long note truncates instead of pushing the grid off the screen.
    @Test func noteCardCapsItsHeight() {
        let card = LiveNoteCardView()
        card.configure(note: String(repeating: "Cue the band. ", count: 12))
        let capped = card.height(forWidth: 320)
        card.configure(note: String(repeating: "Cue the band. ", count: 120))
        #expect(card.height(forWidth: 320) == capped)
    }

    @Test func noteCardHasNoHeightWithoutRoomForText() {
        let card = LiveNoteCardView()
        card.configure(note: "Cue the band")
        #expect(card.height(forWidth: 0) == 0)
    }
}
