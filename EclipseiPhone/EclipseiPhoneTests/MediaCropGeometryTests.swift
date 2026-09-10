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

    // MARK: - fillRect / fitRect

    @Test func fillAndFitBracketThePhoto() {
        let size = CGSize(width: 1200, height: 1600)
        let fill = MediaCropGeometry.fillRect(in: size, aspect: landscape)
        let fit = MediaCropGeometry.fitRect(in: size, aspect: landscape)
        #expect(abs(fill.width - 1200) < 0.01)
        #expect(abs(fill.height - 675) < 0.01)
        #expect(abs(fill.midY - 800) < 0.01)
        #expect(abs(fit.height - 1600) < 0.01)
        #expect(abs(fit.width - 2844.44) < 0.01)
        #expect(abs(fit.midX - 600) < 0.01)
    }

    // MARK: - placed

    @Test func placedSlidesAnOverhangingRectInsteadOfTrimmingIt() throws {
        // Trimming is what produced the thin strip: the shape must survive.
        let size = CGSize(width: 1000, height: 800)
        let moved = try #require(
            MediaCropGeometry.placed(
                CGRect(x: 900, y: 700, width: 400, height: 225), in: size
            )
        )
        #expect(abs(moved.width - 400) < 0.01)
        #expect(abs(moved.height - 225) < 0.01)
        #expect(abs(moved.maxX - 1000) < 0.01)
        #expect(abs(moved.maxY - 800) < 0.01)
    }

    @Test func placedKeepsThePhotoInsideARectWiderThanIt() throws {
        // Between Fill and Fit: the rect is wider than the photo, so the photo may
        // slide within it but not leave it — no bar wider than the slack on either side.
        let size = CGSize(width: 400, height: 400)
        let placed = try #require(
            MediaCropGeometry.placed(
                CGRect(x: -300, y: 50, width: 600, height: 337.5), in: size
            )
        )
        #expect(abs(placed.width - 600) < 0.01)
        #expect(abs(placed.minX - (-200)) < 0.01, "photo's right edge stays on screen")
        #expect(abs(placed.minY - 50) < 0.01)
    }

    @Test func placedShrinksARectLargerThanFitToFit() throws {
        let size = CGSize(width: 400, height: 400)
        let placed = try #require(
            MediaCropGeometry.placed(
                CGRect(x: -400, y: -200, width: 1600, height: 900), in: size
            )
        )
        let fit = MediaCropGeometry.fitRect(in: size, aspect: 1600.0 / 900.0)
        #expect(abs(placed.width - fit.width) < 0.01)
        #expect(abs(placed.height - fit.height) < 0.01)
        // At Fit the photo may still sit anywhere along the slack axis, but not leave.
        #expect(placed.minX <= 0.01)
        #expect(placed.maxX >= size.width - 0.01)
        #expect(abs(placed.minY) < 0.01)
    }

    @Test func placedRejectsADegenerateRect() {
        let size = CGSize(width: 100, height: 100)
        #expect(MediaCropGeometry.placed(.zero, in: size) == nil)
        #expect(
            MediaCropGeometry.placed(
                CGRect(x: 0, y: 0, width: 10, height: 10),
                in: CGSize(width: 0, height: 0)
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
        // A full-width strip reshaped to 9:16 is taller than the photo: that is Fit for
        // this photo, with bars above and below, not a crop squeezed inside it.
        let size = CGSize(width: 1200, height: 1600)
        let crop = try #require(
            MediaCropGeometry.resolved(
                CGRect(x: 0, y: 0, width: 1200, height: 300),
                in: size,
                aspect: MediaAspect.vertical
            )
        )
        #expect(abs(crop.width / crop.height - MediaAspect.vertical) < 0.001)
        #expect(abs(crop.width - 1200) < 0.01)
        #expect(crop.minY <= 0.01)
        #expect(crop.maxY >= size.height - 0.01)
    }

    @Test func showsBarsOnlyWhenTheRectLeavesThePhoto() {
        let size = CGSize(width: 1000, height: 1000)
        #expect(!MediaCropGeometry.showsBars(CGRect(x: 0, y: 200, width: 1000, height: 562), in: size))
        #expect(MediaCropGeometry.showsBars(CGRect(x: -100, y: 200, width: 1200, height: 675), in: size))
    }
}
