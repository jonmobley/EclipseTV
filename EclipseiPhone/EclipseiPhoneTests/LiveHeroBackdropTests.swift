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

    @Test func landscapeLeadingColumnUsesTheBackdrop() {
        #expect(
            LiveHeroBackdrop.isVisible(showsLiveHero: true, isSideBySideChrome: true)
        )
    }

    @Test func homeHidesTheBackdrop() {
        #expect(
            LiveHeroBackdrop.isVisible(showsLiveHero: false, isSideBySideChrome: false)
                == false
        )
    }
}
