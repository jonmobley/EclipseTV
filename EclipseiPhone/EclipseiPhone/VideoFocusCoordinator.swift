//
//  VideoFocusCoordinator.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import AVKit
import UIKit

// MARK: - Adopter

/// Phone-screen video that stops while Eclipse is not the frontmost app.
///
/// Losing focus is a pause, never a teardown: the adopter keeps its player and
/// playhead so returning to Eclipse picks up exactly where the user left off.
@MainActor
protocol FocusSuspendableVideo: AnyObject {

    /// Whether playback is running (or waiting to run) right now.
    ///
    /// Only running video is suspended, so video the user paused by hand stays
    /// paused when they come back.
    var isPlayingForFocus: Bool { get }

    /// Pauses playback because Eclipse is no longer frontmost.
    func suspendForFocusLoss()

    /// Resumes playback that `suspendForFocusLoss()` paused.
    func resumeAfterFocusGain()
}

// MARK: - Coordinator

/// Pauses phone-screen video when Eclipse leaves the foreground, and resumes on return.
///
/// Only video playing *on the phone* registers here — hero Practice Mode playback and
/// the fullscreen previews. Two neighbours deliberately keep going while the app is
/// minimized and must never be registered:
///
/// - AirPlay / HDMI program output, which `ExternalDisplayManager` holds alive so the
///   TV does not fall back to mirroring the phone.
/// - Ambient music, which owns the `audio` background mode.
@MainActor
final class VideoFocusCoordinator {

    static let shared = VideoFocusCoordinator()

    /// True from the moment focus is lost until the app is active again.
    private(set) var isFocusLost = false

    private let center: NotificationCenter
    private var registrations: [Registration] = []
    private var observers: [NSObjectProtocol] = []

    /// Weak entry so an adopter never has to unregister before `deinit`.
    private final class Registration {
        weak var video: (any FocusSuspendableVideo)?
        /// True while this coordinator is the reason the video is paused.
        var isSuspended = false

        init(_ video: any FocusSuspendableVideo) {
            self.video = video
        }
    }

    /// - Parameter center: Source of the app lifecycle notifications; tests pass
    ///   their own so posting a fake background trip cannot wake the real app.
    init(center: NotificationCenter = .default) {
        self.center = center
        observeLifecycle()
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Registry

    /// Number of live registrations, after dropping released adopters.
    var registeredVideoCount: Int {
        compact()
        return registrations.count
    }

    /// Registers phone-screen video to pause while Eclipse is not frontmost.
    ///
    /// Held weakly and idempotent, so callers can register on every play.
    func register(_ video: any FocusSuspendableVideo) {
        compact()
        guard !registrations.contains(where: { $0.video === video }) else { return }
        registrations.append(Registration(video))
    }

    /// Drops `video` from the registry, forgetting any suspension it was owed.
    func unregister(_ video: any FocusSuspendableVideo) {
        registrations.removeAll { $0.video === video }
        compact()
    }

    // MARK: - Focus

    /// Pauses every registered video that is playing.
    ///
    /// Ignored while focus is already lost: `willResignActive` and
    /// `didEnterBackground` both arrive on one trip out of the app, and the second
    /// must not widen the set of videos owed a resume.
    func applyFocusLoss() {
        guard !isFocusLost else { return }
        isFocusLost = true
        compact()
        for registration in registrations {
            guard let video = registration.video, video.isPlayingForFocus else { continue }
            registration.isSuspended = true
            video.suspendForFocusLoss()
        }
    }

    /// Resumes only the videos this coordinator paused.
    func applyFocusGain() {
        isFocusLost = false
        compact()
        for registration in registrations where registration.isSuspended {
            registration.isSuspended = false
            registration.video?.resumeAfterFocusGain()
        }
    }

    // MARK: - Private

    private func compact() {
        registrations.removeAll { $0.video == nil }
    }

    /// Observes with `queue: nil` so the pause lands on the posting turn of the run
    /// loop. `OperationQueue.main` would enqueue the block instead, letting a frame
    /// of audible video through after the app has already left the foreground.
    /// `UIApplication` posts these on the main thread, so the isolation holds.
    private func observeLifecycle() {
        let lost = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]
        observers = lost.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyFocusLoss() }
            }
        }
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyFocusGain() }
            }
        )
    }
}

// MARK: - AVPlayer Adapter

/// Registers a plain `AVPlayer` with `VideoFocusCoordinator` on its owner's behalf.
///
/// The owner retains this object for as long as the player is on screen; the
/// coordinator's registry is weak, so releasing it unregisters the player.
@MainActor
final class PlayerFocusSuspension: NSObject, FocusSuspendableVideo {

    /// True while Picture in Picture owns the player.
    private(set) var isInPictureInPicture = false

    private weak var player: AVPlayer?

    /// - Parameters:
    ///   - player: Phone-screen player to pause while Eclipse is not frontmost.
    ///   - pictureInPictureHost: System player chrome that can pop `player` out of
    ///     the app. Its delegate is taken over so a PiP session is left alone.
    ///   - coordinator: Registry to join.
    init(
        player: AVPlayer,
        pictureInPictureHost: AVPlayerViewController? = nil,
        coordinator: VideoFocusCoordinator = .shared
    ) {
        self.player = player
        super.init()
        pictureInPictureHost?.delegate = self
        coordinator.register(self)
    }

    /// Treats `waitingToPlayAtSpecifiedRate` as playing: a streaming item that is
    /// still buffering would otherwise start up in the background.
    ///
    /// Picture in Picture is the user asking for playback to continue outside the
    /// app, so a popped-out player is never suspended.
    var isPlayingForFocus: Bool {
        guard let player, !isInPictureInPicture else { return false }
        return player.timeControlStatus != .paused
    }

    func suspendForFocusLoss() {
        player?.pause()
    }

    func resumeAfterFocusGain() {
        player?.play()
    }
}

// MARK: - AVPlayerViewControllerDelegate

extension PlayerFocusSuspension: AVPlayerViewControllerDelegate {

    func playerViewControllerWillStartPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        isInPictureInPicture = true
    }

    func playerViewControllerDidStopPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        isInPictureInPicture = false
    }
}
