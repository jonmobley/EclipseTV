//
//  AudioPlayerController+Session.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Audio Session Lifecycle

extension AudioPlayerController {

    /// Registers for the system audio events every music app has to handle.
    ///
    /// Without these, an interruption leaves `isPlaying` true while the system has already
    /// stopped the player — the mini player and lock screen claim playback over silence —
    /// and pulling headphones keeps the track playing out loud.
    func installSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    // MARK: - Interruptions

    @objc private func handleAudioInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            // The system has already stopped audio; sync our own state so the transport
            // controls stay truthful.
            if isPlaying { pause() }

        case .ended:
            let optionsRaw =
                note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let shouldResume =
                options.contains(.shouldResume) && wasPlayingBeforeInterruption
            wasPlayingBeforeInterruption = false
            if shouldResume, currentTrack != nil { play() }

        @unknown default:
            break
        }
    }

    // MARK: - Route Changes

    @objc private func handleAudioRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        guard reason == .oldDeviceUnavailable else { return }

        let previous =
            note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription
        guard Self.isDetachableOutput(previous) else { return }

        // Headphones or Bluetooth went away — never keep playing out of the speaker.
        if isPlaying { pause() }
    }

    /// Whether a route's output was a wired or wireless listening device the user removed.
    private static func isDetachableOutput(
        _ route: AVAudioSessionRouteDescription?
    ) -> Bool {
        guard let outputs = route?.outputs else { return false }
        let detachable: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .carAudio
        ]
        return outputs.contains { detachable.contains($0.portType) }
    }

    // MARK: - Media Services Reset

    @objc private func handleMediaServicesReset() {
        // Every audio object is invalid after a media services reset; rebuild on demand.
        wasPlayingBeforeInterruption = false
        if isPlaying { pause() }
    }
}
