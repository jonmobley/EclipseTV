//
//  AirPlayVideoTransportTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct AirPlayVideoTransportTests {

    @Test func urlMatchesLocalFile() {
        let id = "clip-1"
        let local = URL(fileURLWithPath: "/tmp/\(id).mp4")
        #expect(AirPlayVideoTransport.url(local, matchesItemId: id, localURL: local))
    }

    @Test func urlMatchesItemIdInLastPathComponent() {
        let id = "clip-1"
        let url = URL(fileURLWithPath: "/media/\(id)")
        #expect(
            AirPlayVideoTransport.url(url, matchesItemId: id, localURL: nil)
        )
    }

    @Test func urlDoesNotMatchOtherItem() {
        let url = URL(fileURLWithPath: "/tmp/other.mp4")
        let local = URL(fileURLWithPath: "/tmp/clip-1.mp4")
        #expect(
            AirPlayVideoTransport.url(url, matchesItemId: "clip-1", localURL: local)
            == false
        )
    }

    @Test func clampedTimeStaysInRange() {
        #expect(AirPlayVideoTransport.clampedTime(-4, duration: 60) == 0)
        #expect(AirPlayVideoTransport.clampedTime(80, duration: 60) == 60)
        #expect(AirPlayVideoTransport.clampedTime(12, duration: 60) == 12)
    }

    @Test func playbackStateScrubsFiniteTimes() {
        let state = AirPlayVideoTransport.playbackState(
            itemId: "clip-1",
            isPlaying: true,
            currentTime: 8,
            duration: 40
        )
        #expect(state.itemId == "clip-1")
        #expect(state.isPlaying)
        #expect(state.currentTime == 8)
        #expect(state.duration == 40)
    }

    @Test func layerOnlyPlaybackStaysInPlayerLayerOnExternalScreen() {
        let player = AVPlayer()
        AirPlayVideoTransport.configureLayerOnlyPlayback(on: player)
        #expect(player.usesExternalPlaybackWhileExternalScreenIsActive == false)
        #expect(player.allowsExternalPlayback == true)
    }

    @Test func resumeSeekToleranceIsQuarterSecond() {
        let tolerance = AirPlayVideoTransport.seekTolerance(precise: false)
        #expect(CMTimeCompare(tolerance, AirPlayVideoTransport.resumeSeekTolerance) == 0)
        let seconds = CMTimeGetSeconds(tolerance)
        #expect(abs(seconds - 0.25) < 0.001)
    }

    @Test func preciseSeekToleranceIsZero() {
        let tolerance = AirPlayVideoTransport.seekTolerance(precise: true)
        #expect(CMTimeCompare(tolerance, .zero) == 0)
    }

    @Test func localFileDisablesStallWaiting() {
        let player = AVPlayer()
        let local = URL(fileURLWithPath: "/tmp/clip.mp4")
        AirPlayVideoTransport.configurePlaybackTiming(on: player, url: local)
        #expect(player.automaticallyWaitsToMinimizeStalling == false)
    }

    @Test func remoteURLKeepsDefaultStallWaiting() {
        let player = AVPlayer()
        let before = player.automaticallyWaitsToMinimizeStalling
        let remote = URL(string: "https://example.com/clip.mp4")!
        AirPlayVideoTransport.configurePlaybackTiming(on: player, url: remote)
        #expect(player.automaticallyWaitsToMinimizeStalling == before)
    }

    @Test @MainActor func presentationViewHasNoTransportChrome() {
        let vc = PresentationViewController()
        _ = vc.view
        #expect(vc.view.isUserInteractionEnabled == false)
        let hasControls = vc.view.subviews.contains { $0 is PlaybackControlsView }
        #expect(hasControls == false)
    }

    @Test func externalDisplayRoleMatchesAirPlayScenes() {
        #expect(
            ExternalDisplayManager.isExternalDisplayRole(
                .windowExternalDisplayNonInteractive
            )
        )
        let legacy = UISceneSession.Role(rawValue: "UIWindowSceneSessionRoleExternalDisplay")
        #expect(ExternalDisplayManager.isExternalDisplayRole(legacy))
        #expect(
            ExternalDisplayManager.isExternalDisplayRole(.windowApplication) == false
        )
    }

    @Test func playbackStateZerosNonFiniteTimes() {
        let state = AirPlayVideoTransport.playbackState(
            itemId: nil,
            isPlaying: false,
            currentTime: .nan,
            duration: .infinity
        )
        #expect(state.currentTime == 0)
        #expect(state.duration == 0)
    }

    @Test func isAtEndDetectsFinishedPlayhead() {
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: 40, duration: 40))
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: 39.98, duration: 40))
    }

    @Test func isAtEndFalseMidPlayback() {
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: 0, duration: 40) == false)
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: 39.5, duration: 40) == false)
    }

    @Test func isAtEndFalseForUnknownDuration() {
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: 5, duration: .nan) == false)
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: 5, duration: 0) == false)
        #expect(AirPlayVideoTransport.isAtEnd(currentTime: .nan, duration: 40) == false)
    }

    @Test func parkedStartTimeUsesFallbackWithoutPlayer() {
        #expect(AirPlayVideoTransport.parkedStartTime(player: nil, fallback: 12) == 12)
    }

    @Test func parkedStartTimeUsesFallbackWhenPlayerIsAtZero() {
        let player = AVPlayer()
        #expect(AirPlayVideoTransport.parkedStartTime(player: player, fallback: 7) == 7)
    }
}
