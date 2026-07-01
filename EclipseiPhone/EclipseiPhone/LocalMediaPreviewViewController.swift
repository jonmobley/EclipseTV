//
//  LocalMediaPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LocalMediaPreviewViewController.swift
import UIKit
import AVKit

/// Fullscreen, read-only preview of a media file stored on the phone (in `LocalMediaStore`).
///
/// Used when the user taps a library item while no Apple TV is connected: instead of an
/// error, the item is shown on the phone (and mirrored to any connected AirPlay display
/// by the caller). Images render from the local file; videos play via an `AVPlayer`.
final class LocalMediaPreviewViewController: UIViewController {

    private let fileURL: URL
    private let isVideo: Bool
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private var player: AVPlayer?

    init(fileURL: URL, isVideo: Bool) {
        self.fileURL = fileURL
        self.isVideo = isVideo
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        if isVideo {
            setupVideo()
        } else {
            setupImage()
        }
        setupCloseButton()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
    }

    // MARK: - Setup

    private func setupCloseButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func setupImage() {
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(contentsOfFile: fileURL.path)
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupVideo() {
        let player = AVPlayer(url: fileURL)
        self.player = player

        let controller = AVPlayerViewController()
        controller.player = player
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)

        player.play()
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
