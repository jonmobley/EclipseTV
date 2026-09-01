//
//  LiveOutputRoutingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct LiveOutputRoutingTests {

    @Test func disconnectedWithoutPracticeOpensPreview() {
        #expect(
            LiveOutputRouting.canMarkLive(
                airPlayConnected: false,
                eclipseTVOnline: false,
                practiceMode: false
            ) == false
        )
    }

    @Test func practiceModeMarksLiveWhenDisconnected() {
        #expect(
            LiveOutputRouting.canMarkLive(
                airPlayConnected: false,
                eclipseTVOnline: false,
                practiceMode: true
            )
        )
    }

    @Test func airPlayMarksLiveEvenWithPracticeOff() {
        #expect(
            LiveOutputRouting.canMarkLive(
                airPlayConnected: true,
                eclipseTVOnline: false,
                practiceMode: false
            )
        )
    }

    @Test func eclipseTVMarksLiveEvenWithPracticeOff() {
        #expect(
            LiveOutputRouting.canMarkLive(
                airPlayConnected: false,
                eclipseTVOnline: true,
                practiceMode: false
            )
        )
    }

    @Test func airPlayScreensaverFallbackIsLiveWhenNothingElseIs() {
        #expect(
            LiveOutputRouting.isScreensaverFallbackLive(
                hasOutputDestination: true,
                isOverlayLive: false,
                isJoinedLive: false,
                isBlackSelected: false,
                isLogoSelected: false,
                hasLibraryLiveItem: false,
                hasLiveSlideshow: false
            )
        )
    }

    @Test func screensaverFallbackIsNotLiveWhenMediaIsLive() {
        #expect(
            LiveOutputRouting.isScreensaverFallbackLive(
                hasOutputDestination: true,
                isOverlayLive: false,
                isJoinedLive: false,
                isBlackSelected: false,
                isLogoSelected: false,
                hasLibraryLiveItem: true,
                hasLiveSlideshow: false
            ) == false
        )
    }

    @Test func screensaverFallbackIsNotLiveWithoutADestination() {
        #expect(
            LiveOutputRouting.isScreensaverFallbackLive(
                hasOutputDestination: false,
                isOverlayLive: false,
                isJoinedLive: false,
                isBlackSelected: false,
                isLogoSelected: false,
                hasLibraryLiveItem: false,
                hasLiveSlideshow: false
            ) == false
        )
    }

    @Test func replacingToolDoesNotTakeLiveWhenNotAlreadyLive() {
        #expect(
            LiveOutputRouting.shouldRefreshLiveAfterReplace(isToolLive: false)
                == false
        )
    }

    @Test func replacingToolRefreshesWhenAlreadyLive() {
        #expect(LiveOutputRouting.shouldRefreshLiveAfterReplace(isToolLive: true))
    }

    @Test func practiceModePlaysLibraryVideoInPhoneHeroWhenDisconnected() {
        #expect(
            LiveOutputRouting.phoneHeroPlaysLibraryVideo(
                airPlayConnected: false,
                eclipseTVOnline: false,
                practiceMode: true
            )
        )
    }

    @Test func phoneHeroDoesNotPlayWhenAirPlayIsConnected() {
        #expect(
            LiveOutputRouting.phoneHeroPlaysLibraryVideo(
                airPlayConnected: true,
                eclipseTVOnline: false,
                practiceMode: true
            ) == false
        )
    }

    @Test func phoneHeroDoesNotPlayWhenEclipseTVIsLinked() {
        #expect(
            LiveOutputRouting.phoneHeroPlaysLibraryVideo(
                airPlayConnected: false,
                eclipseTVOnline: true,
                practiceMode: true
            ) == false
        )
    }

    @Test func remoteVideoMonitorWhenAirPlayOwnsVideo() {
        #expect(
            LiveOutputRouting.usesRemoteVideoMonitor(
                isVideo: true,
                airPlayConnected: true,
                eclipseTVOnline: false
            )
        )
    }

    @Test func remoteVideoMonitorWhenEclipseTVOwnsVideo() {
        #expect(
            LiveOutputRouting.usesRemoteVideoMonitor(
                isVideo: true,
                airPlayConnected: false,
                eclipseTVOnline: true
            )
        )
    }

    @Test func remoteVideoMonitorNotUsedForStills() {
        #expect(
            LiveOutputRouting.usesRemoteVideoMonitor(
                isVideo: false,
                airPlayConnected: true,
                eclipseTVOnline: true
            ) == false
        )
    }

    @Test func remoteVideoMonitorNotUsedInDisconnectedPractice() {
        #expect(
            LiveOutputRouting.usesRemoteVideoMonitor(
                isVideo: true,
                airPlayConnected: false,
                eclipseTVOnline: false
            ) == false
        )
    }

    @Test func webOverlayNeedsAirPlayOrPractice() {
        #expect(
            LiveOutputRouting.canPresentWebOverlay(
                airPlayConnected: false,
                practiceMode: false
            ) == false
        )
        #expect(
            LiveOutputRouting.canPresentWebOverlay(
                airPlayConnected: true,
                practiceMode: false
            )
        )
        #expect(
            LiveOutputRouting.canPresentWebOverlay(
                airPlayConnected: false,
                practiceMode: true
            )
        )
    }
}
