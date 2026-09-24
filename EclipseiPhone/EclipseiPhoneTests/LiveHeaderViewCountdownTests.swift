//
//  LiveHeaderViewCountdownTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewCountdownTests {

    @Test func configureCountdownClockShowsDigitsAndHidesPlaceholder() {
        let header = makeHeader()
        header.configureCountdownClock(text: "5:00", isExpired: false)
        #expect(header.countdownClockLabel.isHidden == false)
        #expect(header.countdownClockLabel.text == "5:00")
        #expect(header.countdownClockLabel.textColor == UIColor.white)
        #expect(header.placeholderIcon.isHidden)
        #expect(header.titleLabel.isHidden)
    }

    @Test func configureCountdownClockExpiredUsesRed() {
        let header = makeHeader()
        header.configureCountdownClock(text: "0:00", isExpired: true)
        #expect(header.countdownClockLabel.text == "0:00")
        #expect(header.countdownClockLabel.textColor == UIColor.systemRed)
    }

    @Test func overlayHidesCountdownClock() {
        let header = makeHeader()
        header.configureCountdownClock(text: "1:00", isExpired: false)
        header.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            showsLiveBadge: false
        )
        #expect(header.countdownClockLabel.isHidden)
        #expect(header.countdownClockLabel.text == nil)
    }

    /// Go-live refreshes the hero twice. The second pass shares the countdown
    /// key, so it must not lift the digits above the dissolve already running.
    ///
    /// Injects a stand-in dissolve: unit hosts often return nil from
    /// `snapshotView(afterScreenUpdates:)`, which would skip the production path
    /// this test is meant to lock down.
    @Test func rebuildingCountdownChromeKeepsDigitsUnderTheDissolve() {
        let header = makeHeader()
        header.configureCountdownClock(text: "5:00", isExpired: false)

        let dissolve = UIView(frame: header.bounds)
        header.addSubview(dissolve)
        header.transitionSnapshot = dissolve
        header.bringSubviewToFront(header.liveBadge)
        header.bringSubviewToFront(header.controls)

        // Same-key rebuild — used to paint digits on top of the in-flight dissolve.
        header.configureCountdownClock(text: "5:00", isExpired: false)

        let clockIndex = header.subviews.firstIndex(of: header.countdownClockLabel)
        let dissolveIndex = header.subviews.firstIndex(of: dissolve)
        let badgeIndex = header.subviews.firstIndex(of: header.liveBadge)
        guard let clockIndex, let dissolveIndex, let badgeIndex else {
            Issue.record("Missing countdown, dissolve, or live badge in the hero")
            return
        }
        #expect(clockIndex < dissolveIndex)
        #expect(dissolveIndex < badgeIndex)
    }

    @Test func applyCountdownClockUpdatesDigits() {
        let header = makeHeader()
        header.configureCountdownClock(text: "1:00", isExpired: false)
        header.applyCountdownClock(text: "0:59", isExpired: false)
        #expect(header.countdownClockLabel.text == "0:59")
        #expect(header.countdownClockLabel.isHidden == false)
    }

    private func makeHeader() -> LiveHeaderView {
        LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    }
}
