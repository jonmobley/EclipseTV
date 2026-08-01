//
//  LocalMediaPreviewPageViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// Single image or video page inside `LocalMediaPreviewViewController`.
///
/// Videos use `AVPlayerLayer` (not `AVPlayerViewController`) so horizontal
/// gallery swipes are not stolen by the system player chrome.
final class LocalMediaPreviewPageViewController: UIViewController {

    let index: Int
    private let item: LocalMediaPreviewItem
    private let imageView = UIImageView()
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    init(item: LocalMediaPreviewItem, index: Int) {
        self.item = item
        self.index = index
        super.init(nibName: nil, bundle: nil)
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
        if item.isVideo {
            setupVideo()
        } else {
            setupImage()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player?.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pausePlayback()
    }

    /// Pauses video when the page is no longer visible.
    func pausePlayback() {
        player?.pause()
    }

    // MARK: - Setup

    private func setupImage() {
        // Match the framing the item gets on the external screen / Apple TV.
        imageView.contentMode = MediaFitSettings.mode(forId: item.id).contentMode
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(contentsOfFile: item.fileURL.path)
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupVideo() {
        let player = AVPlayer(url: item.fileURL)
        player.isMuted = item.isMuted
        player.actionAtItemEnd = item.isLooping ? .none : .pause
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        playerLayer = layer

        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        view.addGestureRecognizer(tap)

        if item.isLooping {
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

    @objc private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
}
