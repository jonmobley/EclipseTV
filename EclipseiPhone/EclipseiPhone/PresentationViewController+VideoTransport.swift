//
//  PresentationViewController+VideoTransport.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Library Video Transport (no on-screen chrome)

extension PresentationViewController {

    /// Snapshot for the phone remote. The TV layer never shows controls.
    var libraryVideoPlaybackState: PlaybackState {
        guard let player, let item = player.currentItem else { return PlaybackState() }
        let current = player.currentTime().seconds
        let duration = item.duration.seconds
        return AirPlayVideoTransport.playbackState(
            itemId: nil,
            isPlaying: player.timeControlStatus == .playing,
            currentTime: current,
            duration: duration
        )
    }

    /// Play/pause the AirPlay library video. Returns false when none is live.
    @discardableResult
    func toggleLibraryVideoPlayback() -> Bool {
        guard let player else { return false }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        notifyVideoTransportChanged()
        return true
    }

    /// Relative skip on the AirPlay library video.
    @discardableResult
    func skipLibraryVideo(by delta: TimeInterval) -> Bool {
        guard let player else { return false }
        let current = player.currentTime().seconds
        guard current.isFinite else { return false }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let target = AirPlayVideoTransport.clampedTime(current + delta, duration: duration)
        seekLibraryVideo(to: target)
        return true
    }

    /// Absolute seek on the AirPlay library video.
    @discardableResult
    func seekLibraryVideo(to position: TimeInterval) -> Bool {
        guard let player else { return false }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let target = AirPlayVideoTransport.clampedTime(position, duration: duration)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.notifyVideoTransportChanged()
        }
        return true
    }

    /// Starts pushing periodic time updates to the phone hero.
    func installVideoTransportObserver() {
        removeVideoTransportObserver()
        guard let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        videoTransportTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            self?.notifyVideoTransportChanged()
        }
        notifyVideoTransportChanged()
    }

    /// Drops the periodic observer (player teardown / leaving video).
    func removeVideoTransportObserver() {
        if let token = videoTransportTimeObserver, let player {
            player.removeTimeObserver(token)
        }
        videoTransportTimeObserver = nil
    }

    private func notifyVideoTransportChanged() {
        NotificationCenter.default.post(
            name: ExternalDisplayManager.videoPlaybackDidChangeNotification,
            object: ExternalDisplayManager.shared
        )
    }
}
