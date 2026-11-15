//
//  GridCameraRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// The ribbon under the live camera hero: frames, then Background, then quick changes.
struct GridCameraRibbonTests {

    @Test func framesThenBackgroundThenQuickChanges() {
        let frame = UUID(), still = UUID()
        #expect(GridCameraRibbonItem.items(
            frameIds: [frame], hasBackground: true, cutawayIds: [still]
        ) == [.frame(frame), .background, .cutaway(still)])
    }

    @Test func noBackgroundTileWithoutABackground() {
        let still = UUID()
        #expect(GridCameraRibbonItem.items(
            frameIds: [], hasBackground: false, cutawayIds: [still]
        ) == [.cutaway(still)])
    }

    @Test func emptyWhenNothingToShow() {
        #expect(GridCameraRibbonItem.items(
            frameIds: [], hasBackground: false, cutawayIds: []
        ).isEmpty)
    }
}
