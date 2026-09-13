//
//  LivePollPracticeChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct LivePollPracticeChromeTests {

    /// A live website, countdown, camera, or PDF keeps the projector while the
    /// host rehearses, so it cannot hide the Practice preview.
    @Test func overlayOnAProjectorStillAllowsPractice() {
        #expect(
            LivePollPracticeChrome.isAvailable(
                photoLive: false,
                toolSelected: false,
                slideshowActive: false,
                overlayOwnsPhoneHero: false
            )
        )
    }

    /// With no display the phone hero *is* the projector, so Practice would have
    /// retired a running countdown from the only output while its tile read live.
    @Test func overlayOnThePhoneHeroTakesTheHeroBack() {
        #expect(
            LivePollPracticeChrome.isAvailable(
                photoLive: false,
                toolSelected: false,
                slideshowActive: false,
                overlayOwnsPhoneHero: true
            ) == false
        )
    }

    @Test func aLivePhotoTakesTheHeroBack() {
        #expect(
            LivePollPracticeChrome.isAvailable(
                photoLive: true,
                toolSelected: false,
                slideshowActive: false,
                overlayOwnsPhoneHero: false
            ) == false
        )
    }

    @Test func blackoutLogoOrScreensaverTakesTheHeroBack() {
        #expect(
            LivePollPracticeChrome.isAvailable(
                photoLive: false,
                toolSelected: true,
                slideshowActive: false,
                overlayOwnsPhoneHero: false
            ) == false
        )
    }

    @Test func aRunningSlideshowTakesTheHeroBack() {
        #expect(
            LivePollPracticeChrome.isAvailable(
                photoLive: false,
                toolSelected: false,
                slideshowActive: true,
                overlayOwnsPhoneHero: false
            ) == false
        )
    }

    // MARK: - Which card owns the Practice preview

    @Test func theRehearsingCardInThisShowOwnsTheHero() {
        let show = UUID()
        let practice = UUID()
        #expect(
            LivePollPracticeChrome.practiceMembership(
                practiceMembershipId: practice,
                practiceShowId: show,
                openShowId: show
            ) == practice
        )
    }

    @Test func nothingRehearsingOwnsNothing() {
        #expect(
            LivePollPracticeChrome.practiceMembership(
                practiceMembershipId: nil,
                practiceShowId: nil,
                openShowId: UUID()
            ) == nil
        )
    }

    /// Practice outlives closing a Show, so an unscoped lookup painted the other
    /// Show's deck (and its "· Practice" title) into this Show's hero.
    @Test func practiceInAnotherShowDoesNotTakeThisShowsHero() {
        #expect(
            LivePollPracticeChrome.practiceMembership(
                practiceMembershipId: UUID(),
                practiceShowId: UUID(),
                openShowId: UUID()
            ) == nil
        )
    }

    /// Practice in Show A must not resurface the hero once Home is showing.
    @Test func homeHasNoPracticeChrome() {
        #expect(
            LivePollPracticeChrome.practiceMembership(
                practiceMembershipId: UUID(),
                practiceShowId: UUID(),
                openShowId: nil
            ) == nil
        )
    }

    /// A stale membership whose card was deleted has no Show to match.
    @Test func aRemovedCardOwnsNothing() {
        #expect(
            LivePollPracticeChrome.practiceMembership(
                practiceMembershipId: UUID(),
                practiceShowId: nil,
                openShowId: UUID()
            ) == nil
        )
    }
}
