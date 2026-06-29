//
//  PresentationViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PresentationViewController.swift
import UIKit
import AVFoundation
import os.log

/// Fullscreen, non-interactive view shown on an AirPlay-connected external display.
/// Renders the currently selected item (image or video) at full resolution while the
/// phone keeps its normal UI. Driven entirely by `ExternalDisplayManager`.
final class PresentationViewController: UIViewController {

    // MARK: - Subviews

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 28, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var imageRequest: RemoteImageRequest?
    private var imageLoadGeneration = 0

    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Presentation")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(imageView)
        view.addSubview(messageLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 60),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -60),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }

    // MARK: - Presentation

    /// Replaces the displayed content. Safe to call repeatedly as the selection changes.
    func show(_ source: PresentationSource) {
        teardownPlayer()
        imageRequest?.cancel()
        imageRequest = nil

        switch source.content {
        case .image(let url):
            showImage(at: url)
        case .video(let url, let isLooping, let isMuted):
            showVideo(at: url, isLooping: isLooping, isMuted: isMuted)
        case .unavailable(let thumbnail, let message):
            showUnavailable(thumbnail: thumbnail, message: message)
        }
    }

    /// Clears all content back to a neutral black screen.
    func showIdle() {
        teardownPlayer()
        imageRequest?.cancel()
        imageRequest = nil
        imageView.image = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()
        messageLabel.text = nil
    }

    // MARK: - Image

    private func showImage(at url: URL) {
        messageLabel.text = nil
        imageView.isHidden = false
        imageView.image = nil
        imageView.alpha = 1.0
        activityIndicator.startAnimating()

        // Local files load directly; HTTPS album URLs go through the shared loader (cache).
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

    // MARK: - Video

    private func showVideo(at url: URL, isLooping: Bool, isMuted: Bool) {
        messageLabel.text = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()

        configureAudioSession(muted: isMuted)

        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        player.actionAtItemEnd = isLooping ? .none : .pause

        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspect
        view.layer.insertSublayer(layer, at: 0)

        self.player = player
        self.playerLayer = layer

        if isLooping {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main) { [weak player] _ in
                    player?.seek(to: .zero)
                    player?.play()
                }
        }

        player.play()
    }

    private func configureAudioSession(muted: Bool) {
        guard !muted else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func teardownPlayer() {
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    // MARK: - Unavailable

    private func showUnavailable(thumbnail: UIImage?, message: String) {
        activityIndicator.stopAnimating()
        imageView.isHidden = thumbnail == nil
        imageView.image = thumbnail
        imageView.alpha = thumbnail == nil ? 1.0 : 0.4
        messageLabel.text = message
    }

    deinit {
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
    }
}
