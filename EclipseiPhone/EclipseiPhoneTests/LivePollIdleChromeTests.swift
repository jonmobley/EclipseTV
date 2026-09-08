//
//  LivePollIdleChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct LivePollIdleChromeTests {

    /// A live website, countdown, camera, or PDF keeps the projector while the
    /// host decides between Practice and Start, so it cannot hide the gate.
    @Test func overlayOnAProjectorStillAllowsPracticeOrStart() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false,
                toolSelected: false,
                slideshowActive: false,
                overlayOwnsPhoneHero: false
            )
        )
    }

    /// With no display the phone hero *is* the projector, so the gate would have
    /// retired a running countdown from the only output while its tile read live.
    @Test func overlayOnThePhoneHeroTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false,
                toolSelected: false,
                slideshowActive: false,
                overlayOwnsPhoneHero: true
            ) == false
        )
    }

    @Test func aLivePhotoTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: true,
                toolSelected: false,
                slideshowActive: false,
                overlayOwnsPhoneHero: false
            ) == false
        )
    }

    @Test func blackoutLogoOrScreensaverTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false,
                toolSelected: true,
                slideshowActive: false,
                overlayOwnsPhoneHero: false
            ) == false
        )
    }

    @Test func aRunningSlideshowTakesTheHeroBack() {
        #expect(
            LivePollIdleChrome.isAvailable(
                photoLive: false,
                toolSelected: false,
                slideshowActive: true,
                overlayOwnsPhoneHero: false
            ) == false
        )
    }

    // MARK: - Which overlays a card tap retires

    /// Practice Mode, website live, no display: the hero is the only output, so
    /// tapping the poll has to end the website — otherwise its tile kept the red
    /// stroke while the tap was refused.
    @Test func websiteOnThePhoneHeroIsRetiredByAPollTap() {
        #expect(
            LivePollIdleChrome.overlayOwnsPhoneHero(
                isOverlayLive: true,
                displayConnected: false,
                isQuestPollLive: false
            )
        )
    }

    /// On AirPlay / HDMI the website keeps the projector until Start; the gate
    /// is phone-only and must not tear the overlay down.
    @Test func websiteOnAProjectorIsLeftAlone() {
        #expect(
            LivePollIdleChrome.overlayOwnsPhoneHero(
                isOverlayLive: true,
                displayConnected: true,
                isQuestPollLive: false
            ) == false
        )
    }

    /// The poll's own projector page is handled by the room branch, not retired.
    @Test func thePollsOwnRoomIsNotRetired() {
        #expect(
            LivePollIdleChrome.overlayOwnsPhoneHero(
                isOverlayLive: true,
                displayConnected: false,
                isQuestPollLive: true
            ) == false
        )
    }

    @Test func nothingToRetireWithoutAnOverlay() {
        #expect(
            LivePollIdleChrome.overlayOwnsPhoneHero(
                isOverlayLive: false,
                displayConnected: false,
                isQuestPollLive: false
            ) == false
        )
    }

    // MARK: - Which card owns idle chrome

    @Test func practiceWinsOverAPendingGate() {
        let show = UUID()
        let practice = UUID()
        let idle = LivePollIdleChrome.idleMembership(
            practiceMembershipId: practice,
            practiceShowId: show,
            gateMembershipId: UUID(),
            gateShowId: show,
            openShowId: show
        )
        #expect(idle?.membershipId == practice)
        #expect(idle?.isPracticing == true)
    }

    @Test func gateOwnsChromeWhenNothingIsPracticing() {
        let show = UUID()
        let gate = UUID()
        let idle = LivePollIdleChrome.idleMembership(
            practiceMembershipId: nil,
            practiceShowId: nil,
            gateMembershipId: gate,
            gateShowId: show,
            openShowId: show
        )
        #expect(idle?.membershipId == gate)
        #expect(idle?.isPracticing == false)
    }

    /// Practice outlives closing a Show, so an unscoped lookup painted the other
    /// Show's deck (and its "· Practice" title) into this Show's hero.
    @Test func practiceInAnotherShowDoesNotTakeThisShowsHero() {
        #expect(
            LivePollIdleChrome.idleMembership(
                practiceMembershipId: UUID(),
                practiceShowId: UUID(),
                gateMembershipId: nil,
                gateShowId: nil,
                openShowId: UUID()
            ) == nil
        )
    }

    @Test func aGateInAnotherShowDoesNotTakeThisShowsHero() {
        #expect(
            LivePollIdleChrome.idleMembership(
                practiceMembershipId: nil,
                practiceShowId: nil,
                gateMembershipId: UUID(),
                gateShowId: UUID(),
                openShowId: UUID()
            ) == nil
        )
    }

    /// Practice in Show A must not resurface the hero once Home is showing.
    @Test func homeHasNoIdleChrome() {
        let show = UUID()
        #expect(
            LivePollIdleChrome.idleMembership(
                practiceMembershipId: UUID(),
                practiceShowId: show,
                gateMembershipId: nil,
                gateShowId: nil,
                openShowId: nil
            ) == nil
        )
    }

    /// A stale membership whose card was deleted has no Show to match.
    @Test func aRemovedCardOwnsNothing() {
        let show = UUID()
        #expect(
            LivePollIdleChrome.idleMembership(
                practiceMembershipId: UUID(),
                practiceShowId: nil,
                gateMembershipId: nil,
                gateShowId: nil,
                openShowId: show
            ) == nil
        )
    }
}
