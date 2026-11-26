//
//  LiveHeaderView+TransportAutoHide.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Video Player Chrome (phone-played video)

/// When the video plays in the hero itself (nothing connected, or a phone
/// Preview), the transport behaves like a video player's: it fades a few seconds
/// into playback, a tap on the picture brings it back, and a tap while it shows
/// tucks it away. It stays up while paused, while a finger is on it, and while
/// VoiceOver runs.
///
/// A TV-driven hero (AirPlay / Eclipse TV monitor) is a remote, not a player, so
/// its transport never hides.
extension LiveHeaderView {

    /// Seconds of playback before the transport fades.
    static let transportAutoHideDelay: TimeInterval = 3
    private static let transportFadeDuration: TimeInterval = 0.25

    /// Alpha the transport and expand control get on top of the collapse fade.
    var transportChromeVisibility: CGFloat { isTransportChromeTucked ? 0 : 1 }

    /// Only the hero's own player hides its transport.
    var transportAutoHides: Bool {
        isLibraryVideoPreviewActive && !UIAccessibility.isVoiceOverRunning
    }

    /// Tap on the playing picture: show the transport, or tuck it if it shows.
    func toggleTransportChrome() {
        if isTransportChromeTucked {
            showTransportChrome()
        } else if transportAutoHides {
            setTransportChromeTucked(true, animated: true)
        }
    }

    /// Brings the transport back and restarts the countdown to fading.
    func showTransportChrome() {
        setTransportChromeTucked(false, animated: true)
        scheduleTransportAutoHide()
    }

    /// Restarts the countdown; while paused there is nothing to count down.
    func scheduleTransportAutoHide() {
        cancelTransportAutoHide()
        guard transportAutoHides, libraryVideoPlaybackState.isPlaying else { return }
        let timer = Timer(timeInterval: Self.transportAutoHideDelay, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.transportAutoHideTimer = nil
                guard self.transportAutoHides,
                      self.libraryVideoPlaybackState.isPlaying,
                      !self.controls.isUserInteracting else { return }
                self.setTransportChromeTucked(true, animated: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        transportAutoHideTimer = timer
    }

    func cancelTransportAutoHide() {
        transportAutoHideTimer?.invalidate()
        transportAutoHideTimer = nil
    }

    /// Called on every playback tick of the hero's own player.
    ///
    /// Paused (or finished) shows the transport for good; playing with the
    /// transport up and no countdown running starts one.
    func noteLibraryVideoPlaybackForTransport(isPlaying: Bool) {
        guard isPlaying else {
            cancelTransportAutoHide()
            if isTransportChromeTucked {
                setTransportChromeTucked(false, animated: true)
            }
            return
        }
        if !isTransportChromeTucked, transportAutoHideTimer == nil,
           !controls.isUserInteracting {
            scheduleTransportAutoHide()
        }
    }

    /// Drops any tucked state when the hero stops playing video itself.
    func resetTransportChrome() {
        cancelTransportAutoHide()
        guard isTransportChromeTucked else { return }
        setTransportChromeTucked(false, animated: false)
    }

    private func setTransportChromeTucked(_ tucked: Bool, animated: Bool) {
        guard isTransportChromeTucked != tucked else { return }
        isTransportChromeTucked = tucked
        let apply = { self.applyCollapseChrome() }
        if animated {
            UIView.animate(
                withDuration: Self.transportFadeDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: apply
            )
        } else {
            apply()
        }
        controls.accessibilityElementsHidden = tucked
    }
}
