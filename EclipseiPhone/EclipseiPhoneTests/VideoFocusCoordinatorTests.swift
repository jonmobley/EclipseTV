//
//  VideoFocusCoordinatorTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Pins "phone video pauses when Eclipse is not frontmost, and only what we paused
//  comes back". The resume set is the whole point: a video the user paused by hand
//  must not start playing because they checked another app, and the second lifecycle
//  notification of one trip to the background must not add anything to the set.
//

import AVFoundation
import AVKit
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct VideoFocusCoordinatorTests {

    /// Own notification center per test: a fake background trip must not reach the
    /// singletons the real app wires to these notifications.
    private func makeCoordinator() -> VideoFocusCoordinator {
        VideoFocusCoordinator(center: NotificationCenter())
    }

    @Test func pausesPlayingVideoAndResumesItOnReturn() {
        let coordinator = makeCoordinator()
        let video = FakeFocusVideo(playing: true)
        coordinator.register(video)

        coordinator.applyFocusLoss()
        #expect(video.suspendCount == 1)
        #expect(video.isPlayingForFocus == false)

        coordinator.applyFocusGain()
        #expect(video.resumeCount == 1)
        #expect(video.isPlayingForFocus)
    }

    @Test func leavesHandPausedVideoPaused() {
        let coordinator = makeCoordinator()
        let video = FakeFocusVideo(playing: false)
        coordinator.register(video)

        coordinator.applyFocusLoss()
        coordinator.applyFocusGain()

        #expect(video.suspendCount == 0)
        #expect(video.resumeCount == 0)
    }

    @Test func secondNotificationOfOneTripDoesNotWidenTheResumeSet() {
        let coordinator = makeCoordinator()
        let hero = FakeFocusVideo(playing: true)
        coordinator.register(hero)
        coordinator.applyFocusLoss()

        // didEnterBackground lands right after willResignActive.
        let late = FakeFocusVideo(playing: true)
        coordinator.register(late)
        coordinator.applyFocusLoss()
        #expect(late.suspendCount == 0)

        coordinator.applyFocusGain()
        #expect(hero.resumeCount == 1)
        #expect(late.resumeCount == 0)
    }

    @Test func registrationIsIdempotent() {
        let coordinator = makeCoordinator()
        let video = FakeFocusVideo(playing: true)
        coordinator.register(video)
        coordinator.register(video)

        coordinator.applyFocusLoss()

        #expect(coordinator.registeredVideoCount == 1)
        #expect(video.suspendCount == 1)
    }

    @Test func unregisteredVideoIsLeftAlone() {
        let coordinator = makeCoordinator()
        let video = FakeFocusVideo(playing: true)
        coordinator.register(video)
        coordinator.unregister(video)

        coordinator.applyFocusLoss()
        coordinator.applyFocusGain()

        #expect(coordinator.registeredVideoCount == 0)
        #expect(video.suspendCount == 0)
        #expect(video.resumeCount == 0)
    }

    @Test func releasedVideoDropsOutOfTheRegistry() {
        let coordinator = makeCoordinator()
        do {
            coordinator.register(FakeFocusVideo(playing: true))
        }
        #expect(coordinator.registeredVideoCount == 0)
        coordinator.applyFocusLoss()
        coordinator.applyFocusGain()
    }

    @Test func lifecycleNotificationsDriveTheCoordinator() {
        let center = NotificationCenter()
        let coordinator = VideoFocusCoordinator(center: center)
        let video = FakeFocusVideo(playing: true)
        coordinator.register(video)

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        #expect(coordinator.isFocusLost)
        #expect(video.suspendCount == 1)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(video.suspendCount == 1)

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(coordinator.isFocusLost == false)
        #expect(video.resumeCount == 1)
    }

    @Test func playerSuspensionRegistersAndReleases() {
        let coordinator = makeCoordinator()
        let player = AVPlayer(url: URL(fileURLWithPath: "/tmp/eclipse-focus-clip.mp4"))
        do {
            let suspension = PlayerFocusSuspension(player: player, coordinator: coordinator)
            #expect(coordinator.registeredVideoCount == 1)
            // A player that has never been told to play must not be resumed later.
            #expect(suspension.isPlayingForFocus == false)
            coordinator.applyFocusLoss()
            coordinator.applyFocusGain()
            #expect(player.rate == 0)
        }
        #expect(coordinator.registeredVideoCount == 0)
    }

    @Test func pictureInPictureExemptsThePlayer() {
        let coordinator = makeCoordinator()
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: URL(fileURLWithPath: "/tmp/eclipse-focus-clip.mp4"))
        controller.player = player
        let suspension = PlayerFocusSuspension(
            player: player, pictureInPictureHost: controller, coordinator: coordinator
        )
        #expect(controller.delegate === suspension)

        suspension.playerViewControllerWillStartPictureInPicture(controller)
        #expect(suspension.isInPictureInPicture)
        #expect(suspension.isPlayingForFocus == false)

        suspension.playerViewControllerDidStopPictureInPicture(controller)
        #expect(suspension.isInPictureInPicture == false)
    }
}

// MARK: - Fake

@MainActor
private final class FakeFocusVideo: FocusSuspendableVideo {

    private(set) var suspendCount = 0
    private(set) var resumeCount = 0
    var isPlayingForFocus: Bool

    init(playing: Bool) {
        isPlayingForFocus = playing
    }

    func suspendForFocusLoss() {
        suspendCount += 1
        isPlayingForFocus = false
    }

    func resumeAfterFocusGain() {
        resumeCount += 1
        isPlayingForFocus = true
    }
}
