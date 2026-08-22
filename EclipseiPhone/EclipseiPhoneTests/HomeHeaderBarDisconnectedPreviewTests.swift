//
//  HomeHeaderBarDisconnectedPreviewTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct HomeHeaderBarDisconnectedPreviewTests {

    @Test func previewControlShowsInShowModeWhenNothingIsConnected() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.paused)
        #expect(bar.disconnectedPreviewButton.isHidden == false)
    }

    @Test func previewControlHidesWhenAirPlayConnects() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setPresenting(true)
        bar.setConnectionState(.paused)
        #expect(bar.disconnectedPreviewButton.isHidden == true)
    }

    @Test func previewControlHidesWhenEclipseTVIsLinked() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(true)
        bar.setPresenting(false)
        bar.setConnectionState(.connected)
        #expect(bar.disconnectedPreviewButton.isHidden == true)
    }

    @Test func previewControlHidesOnHome() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 52))
        bar.setShowModeChrome(false)
        bar.setPresenting(false)
        bar.setConnectionState(.paused)
        #expect(bar.disconnectedPreviewButton.isHidden == true)
    }
}
