//
//  CountdownClockFaceTests.swift
//  EclipseiPhoneTests
//
//  Caption and "Card behind numbers" plate on the output clock.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct CountdownClockFaceTests {

    private let canvas = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func plateAndCaptionAreDrawnAboveTheDigits() throws {
        let label = UILabel()
        let face = CountdownClockFace(caption: "Doors open in", showsPlate: true)
        CountdownClockLayout.default.apply(
            to: label, text: "5:00", isExpired: false, face: face, in: canvas
        )
        #expect(label.backgroundColor == CountdownClockFace.plateColor)
        #expect(label.layer.cornerRadius > 0)
        let caption = try #require(label.viewWithTag(CountdownClockFace.captionTag) as? UILabel)
        #expect(caption.isHidden == false)
        #expect(caption.attributedText?.string == "DOORS OPEN IN")
        #expect(caption.frame.maxY < 0)
        // The whole block (caption on top) stays on the canvas.
        #expect(label.frame.minY + caption.frame.minY >= 0)
        #expect(label.frame.maxX <= canvas.width)
    }

    @Test func simpleStyleDropsThePlateAndEmptyCaptionHidesTheChip() {
        let label = UILabel()
        CountdownClockLayout.default.apply(
            to: label, text: "5:00", isExpired: false,
            face: CountdownClockFace(caption: "Up next", showsPlate: true), in: canvas
        )
        CountdownClockLayout.default.apply(
            to: label, text: "5:00", isExpired: false,
            face: CountdownClockFace(caption: "", showsPlate: false), in: canvas
        )
        #expect(label.backgroundColor == .clear)
        #expect(label.layer.cornerRadius == 0)
        #expect(label.viewWithTag(CountdownClockFace.captionTag)?.isHidden == true)
    }

    @Test func plainFaceKeepsTheOldDigitFrame() {
        let label = UILabel()
        let layout = CountdownClockLayout.default
        layout.apply(to: label, text: "5:00", isExpired: false, in: canvas)
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: layout.fontSize(in: canvas.size), weight: .semibold
        )
        #expect(label.frame == layout.labelFrame(text: "5:00", font: font, in: canvas))
    }
}
