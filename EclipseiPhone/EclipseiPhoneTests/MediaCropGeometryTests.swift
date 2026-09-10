//
//  MediaCropGeometryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// The two corrections every crop goes through, in isolation.
///
/// Both used to be duplicated per consumer, and the consumers that skipped them are how
/// a framed still came out as a thin band.
struct MediaCropGeometryTests {

    private let landscape = MediaAspect.landscape

    // MARK: - atAspect

    @Test func atAspectGrowsHeightForATooWideRect() {
        let corrected = MediaCropGeometry.atAspect(
            CGRect(x: 0, y: 0, width: 320, height: 40), landscape
        )
        #expect(abs(corrected.width - 320) < 0.01)
        #expect(abs(corrected.height - 180) < 0.01)
    }

    @Test func atAspectGrowsWidthForATooTallRect() {
        let corrected = MediaCropGeometry.atAspect(
            CGRect(x: 0, y: 0, width: 100, height: 200), landscape
        )
        #expect(abs(corrected.height - 200) < 0.01)
        #expect(abs(corrected.width - 355.56) < 0.01)
    }

    @Test func atAspectKeepsTheCentre() {
        let rect = CGRect(x: 100, y: 250, width: 400, height: 40)
        let corrected = MediaCropGeometry.atAspect(rect, landscape)
        #expect(abs(corrected.midX - rect.midX) < 0.01)
        #expect(abs(corrected.midY - rect.midY) < 0.01)
    }

    @Test func atAspectLeavesAnAlreadyCorrectRectAlone() {
        let rect = CGRect(x: 12, y: 34, width: 1600, height: 900)
        let corrected = MediaCropGeometry.atAspect(rect, landscape)
        #expect(abs(corrected.width - rect.width) < 0.01)
        #expect(abs(corrected.height - rect.height) < 0.01)
        #expect(abs(corrected.minX - rect.minX) < 0.01)
    }

    // MARK: - containedIn

    @Test func containedInSlidesAnOverhangingRectInsteadOfTrimmingIt() throws {
        // Trimming is what produced the thin strip: the shape must survive.
        let size = CGSize(width: 1000, height: 800)
        let moved = try #require(
            MediaCropGeometry.containedIn(
                CGRect(x: 900, y: 700, width: 400, height: 225), size
            )
        )
        #expect(abs(moved.width - 400) < 0.01)
        #expect(abs(moved.height - 225) < 0.01)
        #expect(abs(moved.maxX - 1000) < 0.01)
        #expect(abs(moved.maxY - 800) < 0.01)
    }

    @Test func containedInShrinksOnlyWhenTheRectCannotFit() throws {
        let size = CGSize(width: 400, height: 400)
        let fitted = try #require(
            MediaCropGeometry.containedIn(
                CGRect(x: -100, y: 0, width: 800, height: 450), size
            )
        )
        #expect(fitted.width <= size.width + 0.01)
        #expect(fitted.height <= size.height + 0.01)
        #expect(abs(fitted.width / fitted.height - 800.0 / 450.0) < 0.001)
    }

    @Test func containedInRejectsADegenerateRect() {
        let size = CGSize(width: 100, height: 100)
        #expect(MediaCropGeometry.containedIn(.zero, size) == nil)
        #expect(
            MediaCropGeometry.containedIn(
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGSize(width: 0, height: 0)
            ) == nil
        )
    }

    // MARK: - resolved

    @Test func resolvedIsAlwaysTheTargetAspectAndInsideTheImage() throws {
        let size = CGSize(width: 1200, height: 1600)
        let overhanging = CGRect(x: 1100, y: 1500, width: 600, height: 60)
        let crop = try #require(
            MediaCropGeometry.resolved(overhanging, in: size, aspect: landscape)
        )
        #expect(abs(crop.width / crop.height - landscape) < 0.001)
        #expect(crop.minX >= -0.01)
        #expect(crop.minY >= -0.01)
        #expect(crop.maxX <= size.width + 0.01)
        #expect(crop.maxY <= size.height + 0.01)
    }

    @Test func resolvedHandlesTheVerticalTarget() throws {
        let size = CGSize(width: 1200, height: 1600)
        let crop = try #require(
            MediaCropGeometry.resolved(
                CGRect(x: 0, y: 0, width: 1200, height: 300),
                in: size,
                aspect: MediaAspect.vertical
            )
        )
        #expect(abs(crop.width / crop.height - MediaAspect.vertical) < 0.001)
        #expect(crop.maxY <= size.height + 0.01)
    }
}
