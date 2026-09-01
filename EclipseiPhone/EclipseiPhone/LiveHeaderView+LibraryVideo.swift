//
//  LiveHeaderView+LibraryVideo.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - In-Hero Library Video (phone-only live)

extension LiveHeaderView {

    /// True while the phone hero owns local library-video playback.
    var isLibraryVideoPreviewActive: Bool { libraryVideoPlayer != nil }

    /// Snapshot for transport chrome while the phone player is driving.
    var libraryVideoPlaybackState: PlaybackState {
        guard let player = libraryVideoPlayer,
              let item = player.currentItem else { return PlaybackState() }
        let duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
        let current = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        let playing = player.timeControlStatus == .playing
        return PlaybackState(
            isPlaying: playing,
            currentTime: max(0, current),
            duration: max(0, duration)
        )
    }

    /// Plays a library video in the hero when there is no external display.
    ///
    /// Keeps the same player across `refreshLiveHeader` when `itemId` matches.
    func showLibraryVideoPreview(
        url: URL,
        itemId: String,
        isMuted: Bool,
        isLooping: Bool,
        startAt: TimeInterval = 0
    ) {
        if libraryVideoItemId == itemId, libraryVideoPlayer != nil {
            libraryVideoPlayer?.isMuted = isMuted
            libraryVideoIsLooping = isLooping
            setStaticPreviewHidden(true)
            setLibraryVideoFullscreenButtonVisible(true)
            bringLibraryVideoChromeToFront()
            return
        }

        clearLibraryVideoPreview()
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        clearCameraPreview()

        let host = UIView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(host, at: 0)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        libraryVideoHost = host

        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        player.actionAtItemEnd = isLooping ? .none : .pause
        AirPlayVideoTransport.configureLayerOnlyPlayback(on: player)
        if startAt > 0.5 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        libraryVideoPlayer = player
        libraryVideoItemId = itemId
        libraryVideoIsLooping = isLooping

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = host.bounds
        host.layer.addSublayer(layer)
        libraryVideoLayer = layer

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleLibraryVideoTap))
        host.addGestureRecognizer(tap)

        installLibraryVideoEndObserver(for: player)
        installLibraryVideoTimeObserver(for: player)

        setStaticPreviewHidden(true)
        setLibraryVideoFullscreenButtonVisible(true)
        bringLibraryVideoChromeToFront()
        player.play()
        pushLibraryVideoPlaybackToControls()
    }

    /// Stops and removes the in-hero library video player.
    func clearLibraryVideoPreview() {
        if let observer = libraryVideoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            libraryVideoEndObserver = nil
        }
        if let token = libraryVideoTimeObserver, let player = libraryVideoPlayer {
            player.removeTimeObserver(token)
            libraryVideoTimeObserver = nil
        }
        libraryVideoPlayer?.pause()
        libraryVideoPlayer = nil
        libraryVideoLayer?.removeFromSuperlayer()
        libraryVideoLayer = nil
        libraryVideoHost?.removeFromSuperview()
        libraryVideoHost = nil
        libraryVideoItemId = nil
        setLibraryVideoFullscreenButtonVisible(false)
        setStaticPreviewHidden(false)
    }

    /// Toggles play/pause on the in-hero library video player.
    @discardableResult
    func toggleLibraryVideoPlayback() -> Bool {
        guard let player = libraryVideoPlayer else { return false }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
        pushLibraryVideoPlaybackToControls()
        return true
    }

    /// Relative skip on the in-hero library video player.
    @discardableResult
    func skipLibraryVideo(by delta: TimeInterval) -> Bool {
        guard let player = libraryVideoPlayer else { return false }
        let current = player.currentTime().seconds
        guard current.isFinite else { return false }
        let duration = player.currentItem?.duration.seconds ?? .nan
        var target = current + delta
        if duration.isFinite {
            target = min(max(0, target), duration)
        } else {
            target = max(0, target)
        }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.pushLibraryVideoPlaybackToControls()
        }
        return true
    }

    /// Absolute seek on the in-hero library video player.
    @discardableResult
    func seekLibraryVideo(to position: TimeInterval) -> Bool {
        guard let player = libraryVideoPlayer else { return false }
        let duration = player.currentItem?.duration.seconds ?? .nan
        var target = max(0, position)
        if duration.isFinite { target = min(target, duration) }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.pushLibraryVideoPlaybackToControls()
        }
        return true
    }

    /// Pauses the in-hero player (e.g. before opening fullscreen Preview).
    func pauseLibraryVideoPreview() {
        libraryVideoPlayer?.pause()
        pushLibraryVideoPlaybackToControls()
    }

    /// Resumes the in-hero player after fullscreen Preview dismisses.
    ///
    /// - Parameter time: Optional seek so the hero matches where Preview left off.
    func resumeLibraryVideoPreview(at time: TimeInterval? = nil) {
        if let time, time > 0.5 {
            let cm = CMTime(seconds: time, preferredTimescale: 600)
            libraryVideoPlayer?.seek(
                to: cm, toleranceBefore: .zero, toleranceAfter: .zero
            )
        }
        libraryVideoPlayer?.play()
        pushLibraryVideoPlaybackToControls()
    }

    /// Keeps the player layer sized to the host after layout / collapse.
    func layoutLibraryVideoPreviewIfNeeded() {
        guard let host = libraryVideoHost else { return }
        libraryVideoLayer?.frame = host.bounds
    }

    /// Shows or hides the enter-fullscreen control for phone-local library video.
    func setLibraryVideoFullscreenButtonVisible(_ visible: Bool) {
        guard visible else {
            libraryVideoFullscreenButton?.removeFromSuperview()
            libraryVideoFullscreenButton = nil
            return
        }
        if libraryVideoFullscreenButton != nil {
            bringLibraryVideoChromeToFront()
            return
        }
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "arrow.up.left.and.arrow.down.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.accessibilityLabel = "Full Screen"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.onRequestFullscreen?()
        }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
        libraryVideoFullscreenButton = button
        bringLibraryVideoChromeToFront()
    }

    // MARK: - Private

    private func installLibraryVideoEndObserver(for player: AVPlayer) {
        libraryVideoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self, weak player] _ in
            guard let self, let player else { return }
            if self.libraryVideoIsLooping {
                player.seek(to: .zero)
                player.play()
            } else {
                player.pause()
            }
            self.pushLibraryVideoPlaybackToControls()
        }
    }

    private func installLibraryVideoTimeObserver(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        libraryVideoTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            self?.pushLibraryVideoPlaybackToControls()
        }
    }

    private func pushLibraryVideoPlaybackToControls() {
        updatePlayback(libraryVideoPlaybackState)
    }

    private func bringLibraryVideoChromeToFront() {
        if let host = libraryVideoHost {
            insertSubview(host, at: 0)
        }
        bringWebPreviewChromeToFront()
        if let fullscreen = libraryVideoFullscreenButton {
            bringSubviewToFront(fullscreen)
        }
    }

    @objc fileprivate func handleLibraryVideoTap() {
        guard !isCompactPresentation else { return }
        _ = toggleLibraryVideoPlayback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
