//
//  LibraryThumbnailCellCountdownTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LibraryThumbnailCellCountdownTests {

    @Test func configureCountdownShowsClockAndNameCaption() {
        let cell = makeCell()
        cell.configureCountdown(
            name: "Break",
            seconds: 90,
            isLive: false
        )
        #expect(cell.countdownTimeLabel.isHidden == false)
        #expect(cell.countdownTimeLabel.text == "1:30")
        #expect(cell.captionLabel.text == "Break")
        #expect(cell.captionLabel.numberOfLines == 1)
        #expect(cell.typeIconOverlay.appliedIcon == .countdown)
        #expect(cell.typeIconOverlay.isHidden == false)
        #expect(cell.placeholderIcon.isHidden)
    }

    @Test func configureCountdownExpiredUsesRedClock() {
        let cell = makeCell()
        cell.configureCountdown(
            name: "Break",
            seconds: 0,
            isLive: true,
            isExpired: true
        )
        #expect(cell.countdownTimeLabel.text == "0:00")
        #expect(cell.countdownTimeLabel.textColor == UIColor.systemRed)
    }

    @Test func applyCountdownTimeUpdatesDigitsWithoutClearingCaption() {
        let cell = makeCell()
        cell.configureCountdown(name: "Break", seconds: 60, isLive: true)
        cell.applyCountdownTime(45, isExpired: false)
        #expect(cell.countdownTimeLabel.text == "0:45")
        #expect(cell.captionLabel.text == "Break")
        #expect(cell.typeIconOverlay.appliedIcon == .countdown)
    }

    @Test func resetChromeHidesCountdownClock() {
        let cell = makeCell()
        cell.configureCountdown(name: "Break", seconds: 120, isLive: false)
        cell.resetChrome()
        #expect(cell.countdownTimeLabel.isHidden)
        #expect(cell.countdownTimeLabel.text == nil)
    }

    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }
}
