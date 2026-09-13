//
//  StillDecodeBudgetTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import EclipseiPhone

struct StillDecodeBudgetTests {

    private let panel = CGSize(width: 1920, height: 1080)

    @Test func fillOfPortraitDecodesEnoughForTheCoveredHeight() {
        // 3000×4000 covers 1920×1080 at scale 0.64 → 1920×2560 on screen.
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 3000, height: 4000),
            panelPixelSize: panel,
            placement: .fill
        )
        #expect(edge == 2560)
    }

    @Test func fillOfPanoramaDecodesEnoughForTheCoveredWidth() {
        // 8000×2000 covers 1920×1080 at scale 0.54 → 4320×1080; capped at 2× panel.
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 8000, height: 2000),
            panelPixelSize: panel,
            placement: .fill
        )
        #expect(edge == 3840)
    }

    @Test func fillOfMatchingAspectStaysAtPanelEdge() {
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 3840, height: 2160),
            panelPixelSize: panel,
            placement: .fill
        )
        #expect(edge == 1920)
    }

    @Test func fitOfPortraitOnlyNeedsThePanelHeight() {
        // Letterboxed portrait spans 1080 px tall, so decoding 1920 tall was waste.
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 3000, height: 4000),
            panelPixelSize: panel,
            placement: .fit
        )
        #expect(edge == 1080)
    }

    @Test func fitOfFourByThreeIsHeightBound() {
        // 4:3 letterboxed on 16:9 shows 1440×1080; a 1920-wide decode was waste.
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 4000, height: 3000),
            panelPixelSize: panel,
            placement: .fit
        )
        #expect(edge == 1440)
    }

    @Test func fitOfWiderThanPanelIsWidthBound() {
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 8000, height: 2000),
            panelPixelSize: panel,
            placement: .fit
        )
        #expect(edge == 1920)
    }

    @Test func cropKeepsEnoughPixelsForTheCroppedRegion() {
        // Half-width, half-height 16:9 window on a 3840×2160 photo → 2× the source
        // density is needed, which is the whole file.
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 3840, height: 2160),
            panelPixelSize: panel,
            placement: .crop(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        )
        #expect(edge == 3840)
    }

    @Test func neverUpsamplesASmallSource() {
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 800, height: 600),
            panelPixelSize: panel,
            placement: .fill
        )
        #expect(edge == 800)
    }

    @Test func rotatedPanelFramesAgainstTallEdges() {
        // Vertical Display Mode: 1080×1920 panel, landscape photo filling it.
        let edge = StillDecodeBudget.maxPixelEdge(
            sourcePixelSize: CGSize(width: 4000, height: 3000),
            panelPixelSize: CGSize(width: 1080, height: 1920),
            placement: .fill
        )
        // Cover scale is 1920 / 3000 = 0.64 → 2560×1920; capped at 2 × 1920.
        #expect(edge == 2560)
    }

    @Test func degenerateInputsFallBackToPanelEdge() {
        #expect(
            StillDecodeBudget.maxPixelEdge(
                sourcePixelSize: .zero, panelPixelSize: panel, placement: .fill
            ) == 1920
        )
        #expect(
            StillDecodeBudget.maxPixelEdge(
                sourcePixelSize: CGSize(width: 3000, height: 4000),
                panelPixelSize: panel,
                placement: .crop(CGRect(x: 0, y: 0, width: 0, height: 0.5))
            ) == 1920
        )
    }

    @Test func placementCacheKeysAreDistinct() {
        let crop = StillDecodeBudget.Placement.crop(
            CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        )
        #expect(StillDecodeBudget.Placement.fit.cacheKey != StillDecodeBudget.Placement.fill.cacheKey)
        #expect(crop.cacheKey != StillDecodeBudget.Placement.fill.cacheKey)
        #expect(crop.cacheKey == "crop_0.1000_0.2000_0.5000_0.5000")
    }
}
