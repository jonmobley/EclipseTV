//
//  PresentationViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PresentationViewController.swift
import UIKit
import AVFoundation
import WebKit
import os.log

/// Fullscreen, non-interactive view shown on an AirPlay-connected external display.
/// Renders the currently selected item (image, video, camera, or web page) while the
/// phone keeps its normal UI. Driven entirely by `ExternalDisplayManager`.
final class PresentationViewController: UIViewController {

    // MARK: - Subviews

    /// Fullscreen host for library image/video; content inside is rotated in Vertical.
    let mediaContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Image / player layer target laid out then rotated into `mediaContainer`.
    let mediaContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        // Frame-driven via applyRotatedLayout; keep Autolayout off for this view.
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 28, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Centered phone icon + "Eclipse" shown when nothing is presenting.
    let idleBrandView: UIStackView = {
        let icon = UIImageView(image: UIImage(systemName: "iphone"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.45)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96)
        ])

        let title = UILabel()
        title.text = "Eclipse"
        title.textColor = UIColor.white.withAlphaComponent(0.55)
        title.font = .systemFont(ofSize: 32, weight: .semibold)
        title.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, title])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    /// Host for the live camera preview; rotated for vertically mounted TVs.
    let cameraContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let cameraPreviewView = CameraPreviewView()

    /// Host for the scaled/rotated web view on the external display.
    let webContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    var webView: WKWebView?

    var playerLayer: AVPlayerLayer?
    var player: AVPlayer?
    var loopObserver: NSObjectProtocol?
    var imageRequest: RemoteImageRequest?
    var imageLoadGeneration = 0
    var settingsObserver: NSObjectProtocol?

    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Presentation")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(mediaContainer)
        mediaContainer.addSubview(mediaContentView)
        mediaContentView.addSubview(imageView)
        view.addSubview(idleBrandView)
        view.addSubview(messageLabel)
        view.addSubview(activityIndicator)
        view.addSubview(cameraContainer)
        view.addSubview(webContainer)
        cameraContainer.addSubview(cameraPreviewView)
        // Frame-driven via applyRotatedLayout — Auto Layout size constraints
        // collapse the preview to zero and black the TV (same as mediaContentView).
        cameraPreviewView.translatesAutoresizingMaskIntoConstraints = true

        NSLayoutConstraint.activate([
            mediaContainer.topAnchor.constraint(equalTo: view.topAnchor),
            mediaContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mediaContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mediaContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // mediaContentView is positioned by applyRotatedLayout (bounds/center/transform),
            // not Auto Layout — constraints here would collapse it to zero and black the TV.
            imageView.topAnchor.constraint(equalTo: mediaContentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: mediaContentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: mediaContentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: mediaContentView.trailingAnchor),

            idleBrandView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            idleBrandView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 60),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -60),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            cameraContainer.topAnchor.constraint(equalTo: view.topAnchor),
            cameraContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cameraContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webContainer.topAnchor.constraint(equalTo: view.topAnchor),
            webContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        settingsObserver = NotificationCenter.default.addObserver(
            forName: ExternalOutputSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyMediaLayout()
            self?.applyCameraLayout()
            self?.applyWebLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !mediaContainer.isHidden {
            applyMediaLayout()
        }
        if !cameraContainer.isHidden {
            applyCameraLayout()
        }
        if !webContainer.isHidden {
            applyWebLayout()
        }
    }

    deinit {
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        if let settingsObserver = settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - Presentation

    /// Replaces the displayed content. Safe to call repeatedly as the selection changes.
    func show(_ source: PresentationSource) {
        teardownPlayer()
        imageRequest?.cancel()
        imageRequest = nil
        setIdleBrandVisible(false)

        switch source.content {
        case .image(let url):
            hideCamera()
            hideWeb()
            showImage(at: url)
        case .video(let url, let isLooping, let isMuted):
            hideCamera()
            hideWeb()
            showVideo(at: url, isLooping: isLooping, isMuted: isMuted)
        case .camera:
            hideMediaContainer()
            showCamera()
        case .web(let url):
            hideMediaContainer()
            showWeb(url: url)
        case .unavailable(let thumbnail, _):
            hideCamera()
            hideWeb()
            showUnavailable(thumbnail: thumbnail)
        }
    }

    /// Clears content and shows the idle Eclipse brand on the AirPlay display.
    func showIdle() {
        teardownPlayer()
        hideCamera()
        hideMediaContainer()
        teardownWeb()
        imageRequest?.cancel()
        imageRequest = nil
        imageView.image = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()
        messageLabel.text = nil
        setIdleBrandVisible(true)
    }

    /// Shows or hides the centered phone + "Eclipse" idle mark.
    func setIdleBrandVisible(_ visible: Bool) {
        idleBrandView.isHidden = !visible
    }

    // MARK: - Image

    private func showImage(at url: URL) {
        messageLabel.text = nil
        imageView.isHidden = false
        imageView.image = nil
        imageView.alpha = 1.0
        showMediaContainer()
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
        showMediaContainer()

        configureAudioSession(muted: isMuted)

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

    private func showUnavailable(thumbnail: UIImage?) {
        activityIndicator.stopAnimating()
        messageLabel.text = nil
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
