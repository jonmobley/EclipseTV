//
//  PDFZoomSnapTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Pinch-zoom in the PDF reader catches where the page exactly fills the
//  audience frame's width, and where it exactly fills its height.
//

import Testing
import CoreGraphics
@testable import EclipseiPhone

struct PDFZoomSnapTests {

    private let letter = CGSize(width: 612, height: 792)
    private let frame16x9 = CGSize(width: 366, height: 206)

    @Test func targetsAreFitHeightThenFitWidth() {
        let targets = PDFZoomSnap.targets(
            pageSizeAtScaleOne: letter, container: frame16x9, range: 0.01...10
        )
        #expect(targets.count == 2)
        #expect(abs(targets[0] - 206.0 / 792.0) < 0.0001)
        #expect(abs(targets[1] - 366.0 / 612.0) < 0.0001)
    }

    @Test func targetsOutsideRangeAreDropped() {
        let targets = PDFZoomSnap.targets(
            pageSizeAtScaleOne: letter, container: frame16x9, range: 0.5...10
        )
        #expect(targets.count == 1)
        #expect(abs(targets[0] - 366.0 / 612.0) < 0.0001)
    }

    @Test func nearlyEqualTargetsMerge() {
        let targets = PDFZoomSnap.targets(
            pageSizeAtScaleOne: CGSize(width: 100, height: 100),
            container: CGSize(width: 300, height: 301),
            range: 0.01...10
        )
        #expect(targets.count == 1)
    }

    @Test func emptySizesGiveNoTargets() {
        #expect(PDFZoomSnap.targets(pageSizeAtScaleOne: .zero, container: frame16x9, range: 0.01...10).isEmpty)
        #expect(PDFZoomSnap.targets(pageSizeAtScaleOne: letter, container: .zero, range: 0.01...10).isEmpty)
    }

    @Test func holdsOnlyWithinTheBand() {
        let targets: [CGFloat] = [0.26, 0.6]
        #expect(PDFZoomSnap.target(for: 0.61, in: targets) == 0.6)
        #expect(PDFZoomSnap.target(for: 0.585, in: targets) == 0.6)
        #expect(PDFZoomSnap.target(for: 0.66, in: targets) == nil)
        #expect(PDFZoomSnap.target(for: 0.265, in: targets) == 0.26)
        #expect(PDFZoomSnap.target(for: 0.4, in: targets) == nil)
        #expect(PDFZoomSnap.target(for: 0, in: targets) == nil)
    }
}
