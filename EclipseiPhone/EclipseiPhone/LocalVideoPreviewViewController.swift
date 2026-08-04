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
/// Presented modally (not inside the image gallery pager) so `AVPlayerViewController`
/// transport controls work without fighting horizontal swipes.
final class LocalVideoPreviewViewController: UIViewController {

    private let fileURL: URL
    private let isMuted: Bool
    private let isLooping: Bool
    private let startAt: TimeInterval
    private let closeButton = UIButton(type: .system)
    private var playerController: AVPlayerViewController?
    private var endObserver: NSObjectProtocol?
    /// Fired once on dismiss with the player’s last position (seconds).
    var onDismiss: ((TimeInterval) -> Void)?

    /// - Parameters:
    ///   - fileURL: On-device video file.
    ///   - isMuted: Matches the library item mute flag.
    ///   - isLooping: When true, restarts at end (same as AirPlay / hero).
    ///   - startAt: Initial seek position in seconds.
    init(
        fileURL: URL,
        isMuted: Bool = false,
        isLooping: Bool = false,
        startAt: TimeInterval = 0
    ) {
        self.fileURL = fileURL
        self.isMuted = isMuted
        self.isLooping = isLooping
        self.startAt = startAt
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
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
        view.backgroundColor = .black
        setupPlayer()
        setupCloseButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playerController?.player?.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playerController?.player?.pause()
        guard isBeingDismissed || isMovingFromParent else { return }
        let seconds = playerController?.player?.currentTime().seconds ?? 0
        let position = seconds.isFinite ? max(0, seconds) : 0
        let callback = onDismiss
        onDismiss = nil
        callback?(position)
    }

    // MARK: - Setup

    private func setupPlayer() {
        let player = AVPlayer(url: fileURL)
        player.isMuted = isMuted
        player.actionAtItemEnd = isLooping ? .none : .pause
        if startAt > 0.5 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(controller)
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        playerController = controller

        if isLooping {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
    }

    private func setupCloseButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        closeButton.setImage(
            UIImage(systemName: "xmark.circle.fill", withConfiguration: config),
            for: .normal
        )
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16
            )
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
