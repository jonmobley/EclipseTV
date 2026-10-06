//
//  SlideshowCountdownRingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct SlideshowCountdownRingTests {

    @Test func heroShowsRingOnlyWhileCountingDown() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setSlideshowCountdown(deadline: Date().addingTimeInterval(5), interval: 5)
        #expect(header.slideshowCountdownRing != nil)
        #expect(header.slideshowCountdownRing?.accessibilityValue == "5 seconds")

        header.setSlideshowCountdown(deadline: nil, interval: 0)
        #expect(header.slideshowCountdownRing == nil)
    }

    @Test func ringClearsFitButtonWhenShown() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setSlideshowCountdown(deadline: Date().addingTimeInterval(3), interval: 5)
        #expect(header.slideshowCountdownTrailing?.constant == -10)

        header.setScreenFitToggleVisible(true, mode: .fit)
        #expect(header.slideshowCountdownTrailing?.constant == -54)

        header.setScreenFitToggleVisible(false, mode: .fit)
        #expect(header.slideshowCountdownTrailing?.constant == -10)
    }
}
