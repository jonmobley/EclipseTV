//
//  PresentationViewController+Media.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - Library Media (Image / Video)

extension PresentationViewController {

    /// Shows image/video host and applies Landscape / Vertical panel layout.
    func showMediaContainer() {
        mediaContainer.isHidden = false
        applyMediaLayout()
    }

    /// Hides library media and clears transforms.
    func hideMediaContainer() {
        mediaContainer.isHidden = true
        mediaContentView.transform = .identity
        mediaContentView.bounds = .zero
    }

    /// Sizes/rotates library media like camera: Vertical lays out tall then rotates
    /// into the 16:9 AirPlay framebuffer.
    func applyMediaLayout() {
        guard !mediaContainer.isHidden else { return }
        applyRotatedLayout(to: mediaContentView, in: mediaContainer, scale: 1)
        playerLayer?.frame = mediaContentView.bounds
        screensaverView?.frame = mediaContentView.bounds
    }

    /// Shows a still on the primary media surface.
    /// - Parameter fill: Crops the image to fill the panel instead of letterboxing it.
    ///   The Logo always fills regardless of this flag.
    func showImage(at url: URL, fill: Bool) {
        messageLabel.text = nil
        imageView.isHidden = false
        imageView.image = nil
        imageView.alpha = 1.0
        imageView.contentMode = fill || LogoStore.shared.isLogoFileURL(url)
            ? .scaleAspectFill
            : .scaleAspectFit
        teardownScreensaver()
        showMediaContainer()
        activityIndicator.startAnimating()

        if url.isFileURL {
            imageLoadGeneration += 1
            let generation = imageLoadGeneration
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = UIImage(contentsOfFile: url.path)
                DispatchQueue.main.async {
                    guard let self = self, generation == self.imageLoadGeneration else { return }
                    self.activityIndicator.stopAnimating()
                    self.imageView.image = image
                }
            }
        } else {
            imageRequest = RemoteImageLoader.shared.loadImage(from: url) { [weak self] image in
                self?.activityIndicator.stopAnimating()
                self?.imageView.image = image
            }
        }
    }

    /// Plays a video on the primary media surface.
    /// - Parameter startAt: Absolute seconds to seek before the first `play()`.
    func showVideo(at url: URL, isLooping: Bool, isMuted: Bool, startAt: TimeInterval = 0) {
        messageLabel.text = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()
        teardownScreensaver()
        showMediaContainer()

        configureAudioSession(muted: isMuted)

        // Keep the already-decoded incoming player — a new AVPlayer flashes black.
        if adoptIncomingVideoIfAvailable() {
            applyMediaLayout()
            return
        }

        videoReadyObservation = nil
        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        player.actionAtItemEnd = isLooping ? .none : .pause

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        mediaContentView.layer.insertSublayer(layer, at: 0)

        self.player = player
        self.playerLayer = layer
        applyMediaLayout()

        if isLooping {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        if startAt > 0 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
                player?.play()
            }
        } else {
            player.play()
        }
    }

    /// Moves the incoming overlay player onto the primary surface without rebuilding.
    ///
    /// The transition already waited for a displayed frame. Recreating `AVPlayer`
    /// here is what flashed black at the start of live video.
    func adoptIncomingVideoIfAvailable() -> Bool {
        guard let player = incomingPlayer, let layer = incomingPlayerLayer else {
            return false
        }
        incomingVideoReadyObservation = nil
        incomingLayerReadyObservation = nil
        if let loop = incomingLoopObserver {
            loopObserver = loop
            incomingLoopObserver = nil
        }
        incomingPlayer = nil
        incomingPlayerLayer = nil
        layer.removeFromSuperlayer()
        mediaContentView.layer.insertSublayer(layer, at: 0)
        self.player = player
        self.playerLayer = layer
        return true
    }

    /// Plays the muted seamless-loop Screensaver (aspect fill).
    func showScreensaver(at url: URL) {
        messageLabel.text = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()
        showMediaContainer()

        teardownScreensaver()
        let view = SeamlessLoopPlayerView(url: url)
        view.frame = mediaContentView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mediaContentView.insertSubview(view, at: 0)
        screensaverView = view
        applyMediaLayout()
        view.play()
    }

    /// Activates playback audio for AirPlay video / web media (no-op when muted).
    func configureAudioSession(muted: Bool) {
        guard !muted else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    func teardownPlayer() {
        videoReadyObservation = nil
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        teardownScreensaver()
    }

    /// Stops and removes the seamless Screensaver host.
    func teardownScreensaver() {
        screensaverView?.stop()
        screensaverView?.removeFromSuperview()
        screensaverView = nil
    }

    /// Shows an unavailable placeholder thumbnail on the primary media surface.
    func showUnavailable(thumbnail: UIImage?) {
        activityIndicator.stopAnimating()
        messageLabel.text = nil
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 1.0
        imageView.image = thumbnail
        imageView.isHidden = thumbnail == nil
        if thumbnail != nil {
            setIdleBrandVisible(false)
            showMediaContainer()
        } else {
            hideMediaContainer()
            setIdleBrandVisible(true)
        }
    }
}
