//
//  BrowserOrientationFitTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The phone browser stays black until the scene has turned to the Display
//  Mode orientation, so a Landscape layout never flashes on a portrait screen.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct BrowserOrientationFitTests {

    private let portrait = CGSize(width: 393, height: 852)
    private let landscape = CGSize(width: 852, height: 393)

    @Test func landscapeModeIsCoveredWhilePhoneIsStillPortrait() {
        #expect(!BrowserOrientationFit.matches(bounds: portrait, isVertical: false, idiom: .phone))
        #expect(BrowserOrientationFit.matches(bounds: landscape, isVertical: false, idiom: .phone))
    }

    @Test func verticalModeIsCoveredWhilePhoneIsStillLandscape() {
        #expect(!BrowserOrientationFit.matches(bounds: landscape, isVertical: true, idiom: .phone))
        #expect(BrowserOrientationFit.matches(bounds: portrait, isVertical: true, idiom: .phone))
    }

    @Test func iPadIsNeverCovered() {
        #expect(BrowserOrientationFit.matches(bounds: portrait, isVertical: false, idiom: .pad))
        #expect(BrowserOrientationFit.matches(bounds: landscape, isVertical: true, idiom: .pad))
    }

    @Test func emptyBoundsStayCovered() {
        #expect(!BrowserOrientationFit.matches(bounds: .zero, isVertical: false, idiom: .phone))
    }
}
