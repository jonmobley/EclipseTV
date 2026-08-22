//
//  AlbumItemPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVKit

/// Fullscreen, read-only preview of a single album item on the phone. Images load from
/// the item's HTTPS URL at full size; videos stream via an embedded `AVPlayer`.
final class AlbumItemPreviewViewController: UIViewController {

    private let item: AlbumManifestItem
    private let zoomView = ZoomableImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let closeButton = UIButton(type: .system)
    private var loadToken: RemoteImageRequest?
    private var player: AVPlayer?

    init(item: AlbumManifestItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCloseButton()

        if item.isVideo {
            setupVideo()
        } else {
            setupImage()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loadToken?.cancel()
        player?.pause()
    }

    // MARK: - Setup

    private func setupCloseButton() {
        closeButton.applyPreviewCloseAppearance()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func setupImage() {
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(zoomView, belowSubview: closeButton)

        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        view.bringSubviewToFront(closeButton)

        NSLayoutConstraint.activate([
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        guard let url = item.remoteURL else { return }
        activityIndicator.startAnimating()
        loadToken = RemoteImageLoader.shared.loadImage(from: url) { [weak self] image in
            self?.activityIndicator.stopAnimating()
            self?.zoomView.image = image
        }
    }

    private func setupVideo() {
        guard let url = item.remoteURL else { return }
        let player = AVPlayer(url: url)
        self.player = player

        let controller = AVPlayerViewController()
        controller.player = player
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(controller.view, belowSubview: closeButton)
        controller.didMove(toParent: self)

        player.play()
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
