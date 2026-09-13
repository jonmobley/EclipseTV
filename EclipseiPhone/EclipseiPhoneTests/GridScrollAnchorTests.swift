//
//  GridScrollAnchorTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct GridScrollAnchorTests {

    /// The reported bug: bottom of a portrait grid, turn to landscape (shorter
    /// content), turn back. The bottom must still be the bottom in every range.
    @Test func bottomStaysTheBottomAcrossAShorterAndTallerRange() {
        let portrait = GridScrollAnchor(progress: 2400, maxProgress: 2400)
        #expect(portrait.fraction == 1)
        #expect(portrait.progress(forMaxProgress: 900) == 900)

        let landscape = GridScrollAnchor(progress: 900, maxProgress: 900)
        #expect(landscape.progress(forMaxProgress: 2400) == 2400)
    }

    @Test func topStaysTheTop() {
        let anchor = GridScrollAnchor(progress: 0, maxProgress: 2400)
        #expect(anchor.fraction == 0)
        #expect(anchor.progress(forMaxProgress: 900) == 0)
    }

    @Test func midScrollKeepsItsShareOfTheRange() {
        let anchor = GridScrollAnchor(progress: 600, maxProgress: 2400)
        #expect(anchor.fraction == 0.25)
        #expect(anchor.progress(forMaxProgress: 1000) == 250)
    }

    /// Captured mid-bounce past the end, the grid comes back flush to its last
    /// row, not stranded past it.
    @Test func overscrollPastTheEndClampsToTheBottom() {
        let anchor = GridScrollAnchor(progress: 2460, maxProgress: 2400)
        #expect(anchor.fraction == 1)
        #expect(anchor.progress(forMaxProgress: 900) == 900)
    }

    @Test func overscrollAboveTheTopClampsToTheTop() {
        let anchor = GridScrollAnchor(progress: -80, maxProgress: 2400)
        #expect(anchor.fraction == 0)
    }

    /// A range with nothing to scroll has no place to remember and no place to
    /// restore to.
    @Test func unscrollableRangesAreTreatedAsTheTop() {
        let anchor = GridScrollAnchor(progress: 120, maxProgress: 0)
        #expect(anchor.fraction == 0)

        let bottom = GridScrollAnchor(progress: 1, maxProgress: 1)
        #expect(bottom.progress(forMaxProgress: 0) == 0)
        #expect(bottom.progress(forMaxProgress: -40) == 0)
    }
}
