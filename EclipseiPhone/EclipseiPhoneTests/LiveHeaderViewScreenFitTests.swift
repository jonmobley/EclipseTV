//
//  LiveHeaderViewScreenFitTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewScreenFitTests {

    @Test func screenFitToggleStaysTappableWhenVisible() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setScreenFitToggleVisible(true, mode: .fit)
        #expect(header.isUserInteractionEnabled == true)
        #expect(header.screenFitButton != nil)
        #expect(header.screenFitButton?.accessibilityValue == "Fit")
    }

    @Test func screenFitToggleReflectsFillMode() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setScreenFitToggleVisible(true, mode: .fill)
        #expect(header.screenFitButton?.accessibilityValue == "Fill")
        #expect(
            header.screenFitButton?.accessibilityHint
                == "Shows the whole image with letterboxing"
        )
    }

    @Test func heroStopsInteractionWhenScreenFitHides() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.setScreenFitToggleVisible(true, mode: .fit)
        header.setScreenFitToggleVisible(false, mode: .fit)
        #expect(header.screenFitButton == nil)
        #expect(header.isUserInteractionEnabled == false)
    }
}

struct MediaFitModeToggleTests {

    @Test func modesAlternateBetweenFitAndFill() {
        #expect(MediaFitMode.fit.iconName != MediaFitMode.fill.iconName)
        #expect(MediaFitMode.fit.contentMode == .scaleAspectFit)
        #expect(MediaFitMode.fill.contentMode == .scaleAspectFill)
    }
}
