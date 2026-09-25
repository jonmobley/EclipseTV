//
//  CameraStillRibbonCellLiveStrokeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Camera still thumbs draw the red program ring on the still itself.
///
/// The ribbon used to stroke `contentView` only. An opaque cutaway covered that
/// border, so tapping another thumbnail put it on program with no visible stroke.
@MainActor
struct CameraStillRibbonCellLiveStrokeTests {

    @Test func aLiveCutawayDrawsTheRedStrokeOverItsStill() {
        let cell = CameraStillRibbonCell(
            frame: CGRect(x: 0, y: 0, width: 80, height: 45)
        )
        cell.configure(
            image: swatch(),
            symbolName: "photo",
            isLive: true,
            accessibilityLabel: "Quick Change",
            accessibilityHint: "On program"
        )
        #expect(cell.contentView.layer.borderWidth == 3)
        #expect(cell.contentView.layer.borderColor == UIColor.systemRed.cgColor)
        let still = cell.contentView.subviews.compactMap { $0 as? UIImageView }
            .first { $0.image != nil && !$0.isHidden }
        #expect(still?.layer.borderWidth == 3)
        #expect(still?.layer.borderColor == UIColor.systemRed.cgColor)
        #expect(cell.accessibilityValue == "On program")
    }

    @Test func anIdleCutawayKeepsTheHairline() {
        let cell = CameraStillRibbonCell(
            frame: CGRect(x: 0, y: 0, width: 80, height: 45)
        )
        cell.configure(
            image: swatch(),
            symbolName: "photo",
            isLive: false,
            accessibilityLabel: "Quick Change",
            accessibilityHint: "Off"
        )
        #expect(cell.contentView.layer.borderWidth == 1)
        #expect(cell.accessibilityValue == "Off")
    }

    @Test func goingLiveFromIdleMovesTheStrokeOntoTheStill() {
        let cell = CameraStillRibbonCell(
            frame: CGRect(x: 0, y: 0, width: 80, height: 45)
        )
        cell.configure(
            image: swatch(),
            symbolName: "photo",
            isLive: false,
            accessibilityLabel: "Quick Change",
            accessibilityHint: "Off"
        )
        cell.applyLiveStroke(true)
        #expect(cell.contentView.layer.borderWidth == 3)
        #expect(cell.contentView.layer.borderColor == UIColor.systemRed.cgColor)
    }

    @Test func aLiveFrameOverlayUsesTheRedStroke() {
        let cell = CameraFrameRibbonCell(
            frame: CGRect(x: 0, y: 0, width: 80, height: 45)
        )
        cell.configure(image: swatch(), isLive: true)
        let imageView = cell.contentView.subviews.compactMap { $0 as? UIImageView }.first
        #expect(imageView?.layer.borderWidth == 3)
        #expect(imageView?.layer.borderColor == UIColor.systemRed.cgColor)
        #expect(cell.accessibilityValue == "On camera")
    }

    private func swatch() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
