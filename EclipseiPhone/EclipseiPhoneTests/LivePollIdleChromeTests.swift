//
//  LivePollIdleChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct LivePollIdleChromeTests {

    /// A live website, countdown, camera, or PDF keeps the projector while the
    /// host decides between Practice and Start, so it cannot hide the gate.
    @Test func overlayOnProgramStillAllowsPracticeOrStart() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false, toolSelected: false, slideshowActive: false
            )
        )
    }

    @Test func aLivePhotoTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: true, toolSelected: false, slideshowActive: false
            ) == false
        )
    }

    @Test func blackoutLogoOrScreensaverTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false, toolSelected: true, slideshowActive: false
            ) == false
        )
    }

    @Test func aRunningSlideshowTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false, toolSelected: false, slideshowActive: true
            ) == false
        )
    }
}
