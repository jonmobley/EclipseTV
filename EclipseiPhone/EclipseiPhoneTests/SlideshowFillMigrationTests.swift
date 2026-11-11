//
//  SlideshowFillMigrationTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct SlideshowFillMigrationTests {

    @Test func onlyFillSlideshowsHandTheirSlidesFill() {
        let show = UUID()
        let filled = Slideshow(showId: show, name: "Filled", itemIds: ["a.jpg", "b.jpg"], isFill: true)
        let fitted = Slideshow(showId: show, name: "Fitted", itemIds: ["c.jpg"], isFill: false)
        let ids = SlideshowStore.slideIdsCoveredBySlideshowFill([filled, fitted])
        #expect(ids == ["a.jpg", "b.jpg"])
    }

    @Test func newSlideshowsShowNoMasterFill() {
        let slideshow = Slideshow(showId: UUID(), name: "New")
        #expect(SlideshowStore.slideIdsCoveredBySlideshowFill([slideshow]).isEmpty)
    }
}
