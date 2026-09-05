//
//  LiveHeroBackdropTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct LiveHeroBackdropTests {

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
