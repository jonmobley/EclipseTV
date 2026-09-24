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
    @Test func rebuildingCountdownChromeKeepsDigitsUnderTheDissolve() {
        let previous = ExternalOutputSettings.contentTransition
        ExternalOutputSettings.contentTransition = .crossfade
        defer { ExternalOutputSettings.contentTransition = previous }

        let header = makeHeader()
        // The hero opts out of the autoresizing mask, so a bare frame collapses
        // to zero once it joins a view and the dissolve never starts.
        header.translatesAutoresizingMaskIntoConstraints = true
        header.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(header)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // snapshotView returns nil until the hero has been rendered once.
        header.drawHierarchy(in: header.bounds, afterScreenUpdates: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        header.configureOverlay(
            title: "Photo",
            systemImage: nil,
            fillColor: .black,
            thumbnail: UIImage(systemName: "photo"),
            showsLiveBadge: false
        )
        header.configureCountdownClock(text: "5:00", isExpired: false)
        header.configureCountdownClock(text: "5:00", isExpired: false)

        let clockIndex = header.subviews.firstIndex(of: header.countdownClockLabel)
        let badgeIndex = header.subviews.firstIndex(of: header.liveBadge)
        guard let clockIndex, let badgeIndex, clockIndex < badgeIndex else {
            Issue.record("Countdown digits were not under the dissolve")
            window.isHidden = true
            return
        }
        let between = header.subviews[(clockIndex + 1)..<badgeIndex]
        if between.isEmpty {
            let names = header.subviews.map { String(describing: type(of: $0)) }
            Issue.record(
                "No dissolve above the digits. subviews=\(names) bounds=\(header.bounds) inWindow=\(header.window != nil)"
            )
        }
        #expect(!between.isEmpty)
        window.isHidden = true
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
