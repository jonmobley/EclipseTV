// ImageViewController+PlaybackRemote.swift
import UIKit
import AVFoundation
import AVKit

// MARK: - Remote Playback Control

/// Lets the iPhone companion drive playback of the live video (play / pause / seek /
/// skip) and mirrors the TV's real playback state back to it. The TV remains the device
/// that actually plays the video; the phone is a remote surface over its player.
extension ImageViewController {

    // MARK: - Inbound Commands

    /// Applies a remote playback command from the companion to the live video.
    func connectionManager(_ manager: ConnectionManager,
                           didReceivePlaybackCommand action: EclipseShareProtocol.PlaybackAction,
                           position: Double?) {
        // Only videos are controllable; ignore commands when the live item is a photo.
        guard let path = dataSource.getCurrentPath(), MediaItem(path: path).isVideo else {
            logger.info("Ignoring playback command: live item is not a video")
            return
        }

        // Don't fight an open menu or an in-progress reorder.
        if isMoveMode || presentedViewController != nil { return }

        // If the video isn't already playing fullscreen, bring it live first (a play tap
        // doubles as "Make Live"). The player is created asynchronously and auto-plays,
        // so for play/toggle we're done; pause/seek then apply to the live player.
        if isInGridMode || !isVideo {
            if isInGridMode {
                hideGridView()
            } else {
                displayImageAtCurrentIndex()
            }
            if action == .play || action == .toggle {
                return
            }
        }

        applyPlaybackAction(action, position: position)
    }

    private func applyPlaybackAction(_ action: EclipseShareProtocol.PlaybackAction, position: Double?) {
        guard let player = playerView.player else {
            // Player isn't ready yet (just brought live); status will follow once it is.
            broadcastPlaybackStatus()
            return
        }

        switch action {
        case .play:
            player.play()
        case .pause:
            player.pause()
        case .toggle:
            if player.timeControlStatus == .paused {
                player.play()
            } else {
                player.pause()
            }
        case .seek:
            if let position = position { seek(player, toSeconds: position) }
        case .skip:
            seek(player, toSeconds: CMTimeGetSeconds(player.currentTime()) + (position ?? 0))
        }

        broadcastPlaybackStatus()
    }

    private func seek(_ player: AVPlayer, toSeconds seconds: Double) {
        let durationSeconds = player.currentItem.map { CMTimeGetSeconds($0.duration) } ?? 0
        let upperBound = (durationSeconds.isFinite && durationSeconds > 0) ? durationSeconds : seconds
        let clamped = min(max(0, seconds), max(0, upperBound))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.broadcastPlaybackStatus()
        }
    }

    // MARK: - Status Broadcasting

    /// (Re)installs the timer + KVO that stream playback state to companions. Call right
    /// after assigning a new player to `playerView`.
    func installPlaybackStatusObserver(on player: AVPlayer) {
        removePlaybackStatusObserver()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.playerView.player?.timeControlStatus == .playing else { return }
            self.broadcastPlaybackStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackStatusTimer = timer

        playbackTimeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            self?.broadcastPlaybackStatus()
        }

        broadcastPlaybackStatus()
    }

    /// Stops streaming playback state (e.g. when leaving the fullscreen video).
    func removePlaybackStatusObserver() {
        playbackStatusTimer?.invalidate()
        playbackStatusTimer = nil
        playbackTimeControlObservation?.invalidate()
        playbackTimeControlObservation = nil
    }

    /// Sends the live video's current playback state to companions. No-op unless a video
    /// is showing fullscreen.
    func broadcastPlaybackStatus() {
        guard isVideo, !isInGridMode, !playerView.view.isHidden,
              let player = playerView.player,
              let path = dataSource.getCurrentPath() else {
            return
        }

        let isPlaying = player.timeControlStatus == .playing
        let currentSeconds = CMTimeGetSeconds(player.currentTime())
        let durationSeconds = player.currentItem.map { CMTimeGetSeconds($0.duration) } ?? 0

        connectionManager?.sendPlaybackStatus(
            currentId: URL(fileURLWithPath: path).lastPathComponent,
            isPlaying: isPlaying,
            position: currentSeconds.isFinite ? currentSeconds : 0,
            duration: durationSeconds.isFinite ? durationSeconds : 0)
    }

    /// Tells companions the live video is no longer playing (e.g. returned to the grid),
    /// so their scrubber settles into a paused state.
    func broadcastPlaybackStopped() {
        let currentId = dataSource.getCurrentPath().map { URL(fileURLWithPath: $0).lastPathComponent }
        connectionManager?.sendPlaybackStatus(currentId: currentId, isPlaying: false, position: 0, duration: 0)
    }
}
