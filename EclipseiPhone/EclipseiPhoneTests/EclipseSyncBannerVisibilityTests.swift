//
//  EclipseSyncBannerVisibilityTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The iCloud banner shows on Home only, and a dismissal sticks per message.
//

import Testing
@testable import EclipseiPhone

struct EclipseSyncBannerVisibilityTests {

    private let signIn = "Sign in to iCloud in Settings to sync Shows across your devices."
    private let quota = "Your iCloud storage is full. Free up space to resume Eclipse Sync."

    @Test func showsOnHomeWhenSyncIsPaused() {
        #expect(EclipseSyncBannerVisibility.shouldShow(text: signIn, isOnHome: true, dismissedText: nil))
    }

    @Test func hiddenInsideAShow() {
        #expect(!EclipseSyncBannerVisibility.shouldShow(text: signIn, isOnHome: false, dismissedText: nil))
    }

    @Test func hiddenWhenSyncIsHealthy() {
        #expect(!EclipseSyncBannerVisibility.shouldShow(text: nil, isOnHome: true, dismissedText: nil))
    }

    @Test func dismissalSticksForTheSameMessage() {
        #expect(!EclipseSyncBannerVisibility.shouldShow(text: signIn, isOnHome: true, dismissedText: signIn))
    }

    @Test func aDifferentProblemShowsAgain() {
        #expect(EclipseSyncBannerVisibility.shouldShow(text: quota, isOnHome: true, dismissedText: signIn))
    }
}
