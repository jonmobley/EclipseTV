//
//  LiveHeaderViewSlideshowRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewSlideshowRibbonTests {

    @Test func ribbonToggleStaysTappableAfterRibbonHides() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setSlideshowRibbonToggleVisible(true, isOn: true)
        header.allowsSlideshowBrowse = true
        #expect(header.isUserInteractionEnabled == true)

        header.setSlideshowRibbonToggleVisible(true, isOn: false)
        header.allowsSlideshowBrowse = false
        #expect(header.isUserInteractionEnabled == true)
        #expect(header.slideshowRibbonButton != nil)
    }

    @Test func heroStopsInteractionWhenSlideshowEnds() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setSlideshowRibbonToggleVisible(true, isOn: false)
        header.setSlideshowRibbonToggleVisible(false, isOn: false)
        header.allowsSlideshowBrowse = false
        #expect(header.slideshowRibbonButton == nil)
        #expect(header.isUserInteractionEnabled == false)
    }
}
