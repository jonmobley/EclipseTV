//
//  LocalVideoPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import AVKit
import UIKit

/// Fullscreen phone Preview for a local library video using system player chrome.
///
/// This *is* `AVPlayerViewController`, so tap-to-show controls (including Close)
/// are the only chrome — apart from the title floating over the upper third of the
/// picture while the video plays.
final class LocalVideoPreviewViewController: AVPlayerViewController {

    private let fileURL: URL
    private let isMuted: Bool
    private let isLooping: Bool
    private let startAt: TimeInterval
    private let overlayTitle: String?
    /// Title floating over the picture while it plays.
    let overlayTitleLabel = UILabel()
    private var titleCenterY: NSLayoutConstraint?
    private var timeControlObservation: NSKeyValueObservation?
    private var presentationSizeObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var focusSuspension: PlayerFocusSuspension?
    /// Fired once on dismiss with the player’s last position (seconds).
    var onDismiss: ((TimeInterval) -> Void)?

    /// - Parameters:
    ///   - fileURL: On-device video file.
    ///   - isMuted: Matches the library item mute flag.
    ///   - isLooping: When true, restarts at end (same as AirPlay / hero).
    ///   - startAt: Initial seek position in seconds.
    ///   - overlayTitle: Name to float over the picture while it plays; `nil` for none.
    init(
        fileURL: URL,
        isMuted: Bool = false,
        isLooping: Bool = false,
        startAt: TimeInterval = 0,
        overlayTitle: String? = nil
    ) {
        self.fileURL = fileURL
        self.isMuted = isMuted
        self.isLooping = isLooping
        self.startAt = startAt
        self.overlayTitle = overlayTitle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        showsPlaybackControls = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPlayer()
        setupTitleOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTitleOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player?.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
        guard isBeingDismissed || isMovingFromParent else { return }
        let seconds = player?.currentTime().seconds ?? 0
        let position = seconds.isFinite ? max(0, seconds) : 0
        let callback = onDismiss
        onDismiss = nil
        callback?(position)
    }

    // MARK: - Setup

    private func setupPlayer() {
        PresentationAudioSession.activateIfNeeded(muted: isMuted)
        let item = AVPlayer(url: fileURL)
        item.isMuted = isMuted
        item.actionAtItemEnd = isLooping ? .none : .pause
        if startAt > 0.5 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            item.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player = item
        focusSuspension = PlayerFocusSuspension(player: item, pictureInPictureHost: self)
        observePlaybackForTitle(item)

        guard isLooping else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item.currentItem,
            queue: .main
        ) { [weak item] _ in
            item?.seek(to: .zero)
            item?.play()
        }
    }

    // MARK: - Title Overlay

    /// Floating title, a third of the way down the picture.
    ///
    /// Sits in `contentOverlayView` so the system controls stay above it, and takes no
    /// touches so tap-to-show-controls still reaches the player.
    private func setupTitleOverlay() {
        guard let overlayTitle, let overlay = contentOverlayView else { return }
        overlayTitleLabel.text = overlayTitle
        overlayTitleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        overlayTitleLabel.textColor = .white
        overlayTitleLabel.textAlignment = .center
        overlayTitleLabel.numberOfLines = 2
        overlayTitleLabel.lineBreakMode = .byTruncatingTail
        overlayTitleLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        overlayTitleLabel.shadowOffset = CGSize(width: 0, height: 1)
        overlayTitleLabel.accessibilityTraits = .header
        overlayTitleLabel.isUserInteractionEnabled = false
        overlayTitleLabel.alpha = 0
        overlayTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(overlayTitleLabel)

        let centerY = overlayTitleLabel.centerYAnchor.constraint(equalTo: overlay.topAnchor)
        titleCenterY = centerY
        NSLayoutConstraint.activate([
            overlayTitleLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            overlayTitleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: overlay.leadingAnchor, constant: 24
            ),
            overlayTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: overlay.trailingAnchor, constant: -24
            ),
            centerY
        ])
    }

    private func layoutTitleOverlay() {
        guard let overlay = contentOverlayView, let titleCenterY else { return }
        titleCenterY.constant = VideoPreviewTitleLayout.titleCenterY(
            videoBounds: view.convert(videoBounds, to: overlay),
            presentationSize: player?.currentItem?.presentationSize ?? .zero,
            playerBounds: overlay.bounds,
            minimumCenterY: view.safeAreaInsets.top
                + VideoPreviewTitleLayout.minimumTopInset
        )
    }

    /// KVO lands on an arbitrary queue, so both handlers hop onto main.
    ///
    /// `presentationSize` arrives after the first layout pass, and the title is placed
    /// against the picture, so learning the track size has to re-run the layout.
    private func observePlaybackForTitle(_ player: AVPlayer) {
        guard overlayTitle != nil else { return }
        timeControlObservation = player.observe(
            \.timeControlStatus, options: [.initial, .new]
        ) { [weak self] player, _ in
            let isPlaying = player.timeControlStatus != .paused
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyTitleVisibility(isPlaying: isPlaying) }
            }
        }
        presentationSizeObservation = player.currentItem?.observe(
            \.presentationSize, options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.view.setNeedsLayout() }
            }
        }
    }

    private func applyTitleVisibility(isPlaying: Bool) {
        let target: CGFloat = VideoPreviewTitleLayout.isVisible(
            hasTitle: overlayTitle != nil, isPlaying: isPlaying
        ) ? 1 : 0
        guard overlayTitleLabel.alpha != target else { return }
        UIView.animate(withDuration: 0.25) { self.overlayTitleLabel.alpha = target }
    }
}
