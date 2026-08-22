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
/// are the only chrome — no extra overlay X.
final class LocalVideoPreviewViewController: AVPlayerViewController {

    private let fileURL: URL
    private let isMuted: Bool
    private let isLooping: Bool
    private let startAt: TimeInterval
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
        let item = AVPlayer(url: fileURL)
        item.isMuted = isMuted
        item.actionAtItemEnd = isLooping ? .none : .pause
        if startAt > 0.5 {
            let time = CMTime(seconds: startAt, preferredTimescale: 600)
            item.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player = item

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
}
