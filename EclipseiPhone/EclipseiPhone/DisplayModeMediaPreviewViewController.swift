//
//  DisplayModeMediaPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Fullscreen Preview for Show tools (Background / Screensaver) framed like AirPlay.
///
/// Content sits in a Display Mode panel (16:9 or 9:16) and **always aspect-fills**,
/// matching vertical tiles — landscape art is cropped in Vertical mode rather than
/// letterboxed on the phone.
final class DisplayModeMediaPreviewViewController: UIViewController {

    private let fileURL: URL
    private let isVideo: Bool
    private let usesSeamlessLoop: Bool

    private let panelView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.layer.cornerRadius = 16
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()

    private let closeButton = UIButton(type: .system)
    private var loopPlayer: SeamlessLoopPlayerView?
    private var simplePlayer: AVPlayer?
    private var simplePlayerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - fileURL: Local still or video file.
    ///   - isVideo: Plays video instead of showing a still.
    ///   - usesSeamlessLoop: Screensaver dual-player crossfade; otherwise simple loop.
    init(fileURL: URL, isVideo: Bool, usesSeamlessLoop: Bool = false) {
        self.fileURL = fileURL
        self.isVideo = isVideo
        self.usesSeamlessLoop = usesSeamlessLoop && isVideo
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
        view.addSubview(panelView)
        setupCloseButton()
        if isVideo {
            setupVideo()
        } else {
            setupImage()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        panelView.frame = ExternalOutputSettings.displayModePanelRect(in: view.bounds)
        imageView.frame = panelView.bounds
        loopPlayer?.frame = panelView.bounds
        simplePlayerLayer?.frame = panelView.bounds
        view.bringSubviewToFront(closeButton)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loopPlayer?.play()
        simplePlayer?.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loopPlayer?.stop()
        simplePlayer?.pause()
    }

    // MARK: - Setup

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

    private func setupImage() {
        imageView.image = UIImage(contentsOfFile: fileURL.path)
        panelView.addSubview(imageView)
    }

    private func setupVideo() {
        if usesSeamlessLoop {
            let player = SeamlessLoopPlayerView(url: fileURL)
            panelView.addSubview(player)
            loopPlayer = player
            return
        }
        let player = AVPlayer(url: fileURL)
        player.isMuted = false
        player.actionAtItemEnd = .none
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        panelView.layer.addSublayer(layer)
        simplePlayer = player
        simplePlayerLayer = layer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
