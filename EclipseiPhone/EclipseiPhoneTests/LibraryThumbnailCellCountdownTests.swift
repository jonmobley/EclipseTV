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

    @Test func armedEndingAddsASecondCaptionLineAndSpeaksIt() {
        let cell = makeCell()
        cell.configureCountdown(
            name: "Pre-Service",
            seconds: 300,
            isLive: false,
            endHint: CountdownEndAction.next.tileHint
        )
        #expect(cell.captionLabel.text == "Pre-Service\nThen next")
        #expect(cell.captionLabel.numberOfLines == 2)
        #expect(cell.accessibilityLabel == "Pre-Service, 5:00, countdown, then next")
    }

    @Test func holdingEndingLooksLikeItAlwaysDid() {
        let cell = makeCell()
        cell.configureCountdown(
            name: "Pre-Service",
            seconds: 300,
            isLive: false,
            endHint: CountdownEndAction.hold.tileHint
        )
        #expect(cell.captionLabel.text == "Pre-Service")
        #expect(cell.captionLabel.numberOfLines == 1)
        #expect(cell.accessibilityLabel == "Pre-Service, 5:00, countdown")
    }

    @Test func liveTicksKeepTheArmedHint() {
        let cell = makeCell()
        cell.configureCountdown(
            name: "Pre-Service",
            seconds: 300,
            isLive: true,
            endHint: CountdownEndAction.black.tileHint
        )
        cell.applyCountdownTime(12, isExpired: false)
        #expect(cell.countdownTimeLabel.text == "0:12")
        #expect(cell.captionLabel.text == "Pre-Service\nThen black")
    }

    @Test func resetChromeHidesCountdownClock() {
        let cell = makeCell()
        cell.configureCountdown(name: "Break", seconds: 120, isLive: false)
        cell.resetChrome()
        #expect(cell.countdownTimeLabel.isHidden)
        #expect(cell.countdownTimeLabel.text == nil)
    }

    @Test func blackBackgroundKeepsTheFlatCard() {
        let cell = makeCell()
        cell.configureCountdown(name: "Break", seconds: 60, isLive: false)
        #expect(cell.imageView.image == nil)
        #expect(cell.imageView.alpha == 0)
    }

    @Test func backgroundPosterIsDrawnDimmedUnderTheDigits() {
        let cell = makeCell()
        cell.configureCountdown(
            name: "Break",
            seconds: 60,
            isLive: false,
            background: makePoster()
        )
        #expect(cell.imageView.image != nil)
        #expect(cell.imageView.contentMode == .scaleAspectFill)
        #expect(abs(cell.imageView.alpha - (1 - CountdownBackground.scrimAlpha)) < 0.001)
        #expect(cell.cardView.backgroundColor == UIColor.black)
        #expect(cell.countdownTimeLabel.isHidden == false)
        let digitsIndex = cell.cardView.subviews.firstIndex(of: cell.countdownTimeLabel)
        let artIndex = cell.cardView.subviews.firstIndex(of: cell.imageView)
        #expect(digitsIndex != nil && artIndex != nil && digitsIndex! > artIndex!)
    }

    @Test func lateThumbnailLandsAsBackdropNotFullBrightPoster() {
        let cell = makeCell()
        cell.configureCountdown(name: "Break", seconds: 60, isLive: false)
        cell.applyLoadedThumbnail(makePoster())
        #expect(cell.imageView.image != nil)
        #expect(abs(cell.imageView.alpha - (1 - CountdownBackground.scrimAlpha)) < 0.001)
        #expect(cell.cardView.backgroundColor == UIColor.black)
        #expect(cell.countdownTimeLabel.text == "1:00")
    }

    @Test func menuIconIsAFixedRoundedSquareInOriginalColor() {
        let icon = CountdownBackgroundMenuIcon.render(makePoster(width: 320, height: 90))
        #expect(icon.size.width == CountdownBackgroundMenuIcon.side)
        #expect(icon.size.height == CountdownBackgroundMenuIcon.side)
        #expect(icon.renderingMode == .alwaysOriginal)
    }

    @Test func aspectFillCoversTheSquareAndCenters() {
        let bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        let rect = CountdownBackgroundMenuIcon.aspectFillRect(
            for: CGSize(width: 160, height: 90), in: bounds
        )
        #expect(abs(rect.height - 28) < 0.001)
        #expect(rect.width > 28)
        #expect(abs(rect.midX - 14) < 0.001)
    }

    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    private func makePoster(width: CGFloat = 64, height: CGFloat = 36) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
