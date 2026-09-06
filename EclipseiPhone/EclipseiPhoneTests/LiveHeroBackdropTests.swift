//
//  LiveHeroBackdropTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct LiveHeroBackdropTests {

    /// The plate casts a soft shadow along its bottom edge so tiles read as
    /// sliding beneath the preview instead of butting up against it.
    @MainActor
    @Test func plateCastsADownwardShadowOnceLaidOut() {
        let plate = LiveHeroBackdropView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        plate.layoutIfNeeded()
        #expect(plate.backgroundColor == .black)
        #expect(plate.layer.shadowOpacity > 0)
        #expect(plate.layer.shadowOffset.height > 0)
        #expect(plate.layer.shadowPath != nil)
    }

    @MainActor
    @Test func parkedPlateHasNoShadowPath() {
        let plate = LiveHeroBackdropView(frame: .zero)
        plate.layoutIfNeeded()
        #expect(plate.layer.shadowPath == nil)
    }

    @Test func portraitLiveHeroCoversTilesUnderThePreview() {
        #expect(
            LiveHeroBackdrop.isVisible(showsLiveHero: true, isSideBySideChrome: false)
        )
    }

    /// Landscape puts the grid in its own column, so nothing scrolls under the
    /// preview and the plate is pinned to 0×0 in `landscapeChromeConstraints`.
    @Test func landscapeDoesNotNeedTheBackdrop() {
        #expect(
            LiveHeroBackdrop.isVisible(showsLiveHero: true, isSideBySideChrome: true)
                == false
        )
    }

    @Test func homeHidesTheBackdrop() {
        #expect(
            LiveHeroBackdrop.isVisible(showsLiveHero: false, isSideBySideChrome: false)
                == false
        )
    }
}
