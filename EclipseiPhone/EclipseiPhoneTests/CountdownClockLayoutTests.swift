//
//  CountdownClockLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct CountdownClockLayoutTests {

    @Test func defaultFontIsStageSizedOn1080p() {
        let size = CountdownClockLayout.default.fontSize(
            in: CGSize(width: 1920, height: 1080)
        )
        #expect(size > 500)
        #expect(abs(size - 1080 * CountdownClockLayout.defaultFontFraction) < 0.01)
    }

    @Test func scaleClampsToAllowedRange() {
        let tiny = CountdownClockLayout(centerX: 0.5, centerY: 0.5, scale: 0.01)
        #expect(tiny.clampedScale.scale == CountdownClockLayout.minScale)
        let huge = CountdownClockLayout(centerX: 0.5, centerY: 0.5, scale: 9)
        #expect(huge.clampedScale.scale == CountdownClockLayout.maxScale)
    }

    @Test func translationKeepsClockOnCanvas() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let moved = CountdownClockLayout.default.translating(
            by: CGPoint(x: 5000, y: -4000),
            text: "5:00",
            in: bounds
        )
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: moved.fontSize(in: bounds.size),
            weight: .semibold
        )
        let frame = moved.labelFrame(text: "5:00", font: font, in: bounds)
        #expect(frame.minX >= -0.5)
        #expect(frame.minY >= -0.5)
        #expect(frame.maxX <= bounds.width + 0.5)
        #expect(frame.maxY <= bounds.height + 0.5)
    }

    @Test func aspectFittedLetterboxesInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let landscape = CountdownLayoutEditorViewController.aspectFitted(
            16.0 / 9.0, in: bounds
        )
        #expect(abs(landscape.width / landscape.height - 16.0 / 9.0) < 0.01)
        #expect(bounds.contains(landscape))
        let vertical = CountdownLayoutEditorViewController.aspectFitted(
            9.0 / 16.0, in: bounds
        )
        #expect(abs(vertical.width / vertical.height - 9.0 / 16.0) < 0.01)
        #expect(bounds.contains(vertical))
    }
}
