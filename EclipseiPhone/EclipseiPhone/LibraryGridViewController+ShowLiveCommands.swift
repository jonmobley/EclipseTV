//
//  LibraryGridViewController+ShowLiveCommands.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Second-device live remote: transport, countdown, lock

extension LibraryGridViewController {

    /// Sends a command to the director. True when the caller must skip local handling.
    @discardableResult
    func sendShowLiveCommandIfOperator(
        _ verb: ShowLiveCommandVerb,
        value: Double? = nil
    ) -> Bool {
        guard ShowLiveRouting.shouldCommandDirector(
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator
        ) else { return false }
        _ = ShowLiveSession.shared.sendCommand(verb, value: value)
        return true
    }

    func handleIncomingShowLiveCommand(_ note: Notification) {
        guard let command = note.userInfo?[ShowLiveSession.commandKey]
            as? ShowLiveCommand else { return }
        applyIncomingShowLiveCommand(command)
    }

    /// Applies an operator command on the director through the same handlers a
    /// local hero / ⋯ menu tap would use, so lock and destination rules still apply.
    func applyIncomingShowLiveCommand(_ command: ShowLiveCommand) {
        guard ShowLiveSession.shared.isDirector else { return }
        switch command.verb {
        case .videoToggle:
            handleLiveVideoPlayPause()
        case .videoSkip:
            guard let delta = command.value else { return }
            handleLiveVideoSkip(by: delta)
        case .videoSeek:
            guard let position = command.value else { return }
            handleLiveVideoSeek(to: position)
        case .countdownToggleRunning:
            guard ExternalDisplayManager.shared.isCountdownLive else { return }
            CountdownController.shared.toggleRunning()
        case .countdownReset:
            guard ExternalDisplayManager.shared.isCountdownLive else { return }
            CountdownController.shared.reset()
        case .countdownSetDuration:
            guard ExternalDisplayManager.shared.isCountdownLive,
                  let seconds = command.value else { return }
            CountdownController.shared.setDuration(Int(seconds))
            refreshSlideshowRibbonPresentation()
        case .lockToggle:
            toggleLiveOutputLock()
        }
    }

    // MARK: Director → snapshot

    /// Director library-video transport for the snapshot, nil when video is not live.
    var showLiveVideoState: ShowLiveVideoState? {
        let mgr = ExternalDisplayManager.shared
        guard mgr.isLibraryVideoLive else { return nil }
        let state = mgr.libraryVideoPlaybackState
        return ShowLiveVideoState(
            isPlaying: state.isPlaying,
            currentTime: Int(state.currentTime.rounded(.down)),
            duration: Int(state.duration.rounded(.down))
        )
    }

    /// Director countdown clock for the snapshot, nil when no countdown is live.
    var showLiveCountdownState: ShowLiveCountdownState? {
        guard ExternalDisplayManager.shared.isCountdownLive else { return nil }
        let clock = CountdownController.shared
        return ShowLiveCountdownState(
            remaining: clock.remaining, duration: clock.duration, running: clock.running
        )
    }

    // MARK: Operator ← snapshot

    /// Director's countdown as seen by an operator; nil on the director itself.
    var remoteCountdownState: ShowLiveCountdownState? {
        guard ShowLiveSession.shared.isRemoteOperator else { return nil }
        return ShowLiveSession.shared.snapshot?.countdown
    }

    /// True on an operator when `itemId` (or, for nil, any countdown) is the
    /// director's live countdown, so duration edits should go over the wire.
    func isRemoteCountdownLive(_ itemId: UUID?) -> Bool {
        guard ShowLiveSession.shared.isRemoteOperator,
              let snap = ShowLiveSession.shared.snapshot,
              snap.liveKind == .countdown, !snap.isBlackout else { return false }
        guard let itemId else { return true }
        return snap.liveItemId == itemId.uuidString
    }

    /// Scrubber state for the operator hero from the director snapshot.
    func remotePlaybackState(_ snap: ShowLiveSnapshot) -> PlaybackState {
        guard let video = snap.video else { return PlaybackState() }
        return PlaybackState(
            itemId: snap.liveItemId,
            isPlaying: video.isPlaying,
            currentTime: Double(video.currentTime),
            duration: Double(video.duration)
        )
    }

    /// Operator hero clock mirroring the director countdown. Falls back to the
    /// generic overlay when a legacy director sends no clock state.
    func applyRemoteCountdownHeader(_ snap: ShowLiveSnapshot) {
        guard let clock = snap.countdown else {
            applyRemoteOverlayHeader(title: "Countdown", systemImage: "timer")
            return
        }
        let text = CountdownController.displayString(seconds: clock.remaining)
        let isExpired = clock.remaining == 0
        if liveHeader.countdownClockLabel.isHidden {
            liveHeader.configureCountdownClock(text: text, isExpired: isExpired)
        } else {
            liveHeader.applyCountdownClock(text: text, isExpired: isExpired)
        }
    }
}
