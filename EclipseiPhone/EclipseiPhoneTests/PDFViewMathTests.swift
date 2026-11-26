//
//  PDFViewMathTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  PDF presets (Fit / Fill / Two Pages) and page-by-page settling.
//

import CoreGraphics
import Testing
@testable import EclipseiPhone

struct PDFViewMathTests {

    private let letter = CGSize(width: 612, height: 792)
    private let frame16x9 = CGSize(width: 1600, height: 900)

    // MARK: - Presets

    @Test func fitShowsTheWholePortraitPageInAWideFrame() throws {
        let scale = try #require(PDFViewMath.scale(for: .fit, rowSizeAtScaleOne: letter, container: frame16x9))
        #expect(abs(scale - 900 / 792) < 0.0001)
        #expect(letter.width * scale <= frame16x9.width)
    }

    @Test func fillCoversTheFrame() throws {
        let scale = try #require(PDFViewMath.scale(for: .fill, rowSizeAtScaleOne: letter, container: frame16x9))
        #expect(abs(scale - 1600 / 612) < 0.0001)
        #expect(letter.height * scale >= frame16x9.height)
    }

    @Test func twoPagesFitsThePair() throws {
        let pair = CGSize(width: letter.width * 2, height: letter.height)
        let scale = try #require(PDFViewMath.scale(for: .twoPages, rowSizeAtScaleOne: pair, container: frame16x9))
        #expect(pair.width * scale <= frame16x9.width + 0.001)
        #expect(pair.height * scale <= frame16x9.height + 0.001)
        #expect(PDFViewPreset.twoPages.isTwoUp)
        #expect(!PDFViewPreset.fill.isTwoUp)
    }

    @Test func emptySizesHaveNoScale() {
        #expect(PDFViewMath.scale(for: .fit, rowSizeAtScaleOne: .zero, container: frame16x9) == nil)
        #expect(PDFViewMath.scale(for: .fill, rowSizeAtScaleOne: letter, container: .zero) == nil)
    }

    // MARK: - Page by page

    /// Three pages that each fit the 900pt viewport (800pt tall, 20pt gaps).
    private let shortRows: [ClosedRange<CGFloat>] = [0...800, 820...1620, 1640...2440]
    private var shortRange: ClosedRange<CGFloat> { -50...1590 }

    @Test func aSwipeDownMovesOnePage() throws {
        // Page 1 centred: 400 - 450 = -50.
        let target = try #require(PDFViewMath.snapOffset(
            rows: shortRows, offset: -20, projected: 1500, viewport: 900, range: shortRange
        ))
        #expect(abs(target - (1220 - 450)) < 0.001) // page 2 centred, not page 3
    }

    @Test func aSwipeUpMovesBackOnePage() throws {
        let target = try #require(PDFViewMath.snapOffset(
            rows: shortRows, offset: 1500, projected: 200, viewport: 900, range: shortRange
        ))
        #expect(abs(target - 770) < 0.001)
    }

    @Test func aSlowReleaseSettlesOnTheNearestPage() throws {
        let target = try #require(PDFViewMath.snapOffset(
            rows: shortRows, offset: 700, projected: 705, viewport: 900, range: shortRange
        ))
        #expect(abs(target - 770) < 0.001)
    }

    /// Zoomed in: the middle page is 2000pt tall, more than the 900pt viewport.
    private let tallRows: [ClosedRange<CGFloat>] = [0...800, 820...2820, 2840...3640]
    private var tallRange: ClosedRange<CGFloat> { -50...2790 }

    @Test func aTallPageScrollsFreelyInside() {
        let target = PDFViewMath.snapOffset(
            rows: tallRows, offset: 1200, projected: 1500, viewport: 900, range: tallRange
        )
        #expect(target == nil)
    }

    @Test func aGlideStopsAtTheTallPagesEdge() throws {
        let target = try #require(PDFViewMath.snapOffset(
            rows: tallRows, offset: 1500, projected: 2600, viewport: 900, range: tallRange
        ))
        #expect(abs(target - (2820 - 900)) < 0.001)
    }

    @Test func aSwipeFromTheTallPagesEdgeMovesOn() throws {
        let target = try #require(PDFViewMath.snapOffset(
            rows: tallRows, offset: 1920, projected: 2600, viewport: 900, range: tallRange
        ))
        #expect(abs(target - (3240 - 450)) < 0.001) // page 3 centred (clamped to range end)
    }

    @Test func projectedOffsetFollowsVelocity() {
        #expect(PDFViewMath.projectedOffset(100, velocity: 0) == 100)
        #expect(PDFViewMath.projectedOffset(100, velocity: 1000) > 500)
        #expect(PDFViewMath.projectedOffset(100, velocity: -1000) < -300)
    }
}
