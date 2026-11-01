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

    // MARK: - Expand / Collapse

    private static let longNote = String(repeating: "Cue the band. ", count: 40)

    /// Pre-pencil height of a one-line note: subheadline plus the 12 pt insets.
    @Test func shortNoteKeepsItsCollapsedHeight() {
        let card = LiveNoteCardView()
        card.configure(note: "Cue the band")
        let line = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        #expect(abs(card.height(forWidth: 320) - (line + 24)) <= 1)
    }

    @Test func expandedHeightSitsBetweenCollapsedAndTheCap() {
        let card = LiveNoteCardView()
        card.configure(note: Self.longNote)
        let collapsed = card.height(forWidth: 320, maxHeight: 200)
        card.setExpanded(true)
        let expanded = card.height(forWidth: 320, maxHeight: 200)
        #expect(expanded > collapsed)
        #expect(expanded == 200)
    }

    /// With no room to grow the card holds its collapsed size and scrolls.
    @Test func expandedCardNeverDropsBelowCollapsed() {
        let card = LiveNoteCardView()
        card.configure(note: Self.longNote)
        let collapsed = card.collapsedHeight(forWidth: 320)
        card.setExpanded(true)
        #expect(card.height(forWidth: 320, maxHeight: 10) == collapsed)
    }

    @Test func onlyTruncatedNotesToggle() {
        let card = LiveNoteCardView()
        card.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        card.configure(note: "Cue the band")
        #expect(!card.isToggleable)
        card.configure(note: Self.longNote)
        #expect(card.isToggleable)
    }

    /// A rotation can make an expanded note fit; a tap must still bring it back.
    @Test func expandedCardCanAlwaysCollapse() {
        let card = LiveNoteCardView()
        card.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        card.configure(note: "Cue the band")
        card.setExpanded(true)
        #expect(card.isToggleable)
    }

    @Test func collapsedLinesFollowTheWidthClass() {
        #expect(LiveNoteCardView.collapsedLineCount(horizontalSizeClass: .compact) == 3)
        #expect(LiveNoteCardView.collapsedLineCount(horizontalSizeClass: .regular) == 5)
        #expect(LiveNoteCardView.collapsedLineCount(horizontalSizeClass: .unspecified) == 3)
    }

    @Test func aNewItemOrEditedNoteCollapsesTheCard() {
        let change = LibraryGridViewController.liveNoteContentChanged
        #expect(change("a", "note", "b", "note"))
        #expect(change("a", "note", "a", "edited"))
        #expect(change("a", "note", nil, nil))
        #expect(!change("a", "note", "a", "note"))
    }

    @Test func stackedCapIsFortyPercentOfTheSafeArea() {
        #expect(LibraryGridViewController.stackedLiveNoteMaxHeight(safeAreaHeight: 700) == 280)
    }

    @Test func sideBySideCapLeavesThePreviewAtItsCollapsedHeight() {
        #expect(
            LibraryGridViewController.sideBySideLiveNoteMaxHeight(
                columnHeight: 300, heroHeight: 170
            ) == 130
        )
        #expect(
            LibraryGridViewController.sideBySideLiveNoteMaxHeight(
                columnHeight: 100, heroHeight: 170
            ) == 0
        )
    }

    // MARK: - Pencil and VoiceOver

    @Test func pencilRunsOnEditAndTheCardBodyDoesNot() {
        let card = LiveNoteCardView()
        card.configure(note: Self.longNote)
        var edits = 0
        card.onEdit = { edits += 1 }
        card.sendActions(for: .touchUpInside)
        #expect(edits == 0)
        card.pencilButton.sendActions(for: .touchUpInside)
        #expect(edits == 1)
    }

    @Test func emptyPreviewCardHasNoPencilAndAnchorsToItself() {
        let card = MediaNoteCardView()
        card.configure(note: nil)
        #expect(!card.hasNote)
        #expect(card.pencilButton.isHidden)
        #expect(card.editAnchor === card)
        #expect(card.accessibilityElements?.count == 1)
    }

    @Test func voiceOverReadsTheStateOnlyWhenTruncated() throws {
        let card = LiveNoteCardView()
        card.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        card.configure(note: Self.longNote)
        let elements = try #require(card.accessibilityElements)
        #expect(elements.count == 2)
        let body = try #require(elements.first as? UIAccessibilityElement)
        #expect(body.accessibilityLabel == "Note. \(Self.longNote)")
        #expect(body.accessibilityValue == "Collapsed")
        #expect(body.accessibilityCustomActions?.first?.name == "Edit note")
        card.setExpanded(true)
        #expect(body.accessibilityValue == "Expanded")
        card.setExpanded(false)
        card.configure(note: "Cue the band")
        #expect(body.accessibilityValue == nil)
    }
}
