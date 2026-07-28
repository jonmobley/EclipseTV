//
//  AudioNowPlayingViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Expanded ambient Now Playing sheet with transport + scrubber.
final class AudioNowPlayingViewController: UIViewController {

    var onOpenLibrary: (() -> Void)?

    private let artworkView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 12
        view.backgroundColor = UIColor(white: 0.2, alpha: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let scrubber: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    private let elapsedLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let remainingLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let playButton = UIButton(type: .system)
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private var isScrubbing = false
    private var observer: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Now Playing"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Music", style: .plain, target: self, action: #selector(libraryTapped)
        )

        configureButtons()
        layout()
        scrubber.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        scrubber.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside])
        scrubber.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)

        observer = NotificationCenter.default.addObserver(
            forName: AudioPlayerController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Private

    private func configureButtons() {
        let large = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let mid = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: large), for: .normal)
        prevButton.setImage(
            UIImage(systemName: "backward.fill", withConfiguration: mid), for: .normal
        )
        nextButton.setImage(
            UIImage(systemName: "forward.fill", withConfiguration: mid), for: .normal
        )
        for button in [playButton, prevButton, nextButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .label
        }
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
    }

    private func layout() {
        let transport = UIStackView(arrangedSubviews: [prevButton, playButton, nextButton])
        transport.axis = .horizontal
        transport.alignment = .center
        transport.distribution = .equalCentering
        transport.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(artworkView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(scrubber)
        view.addSubview(elapsedLabel)
        view.addSubview(remainingLabel)
        view.addSubview(transport)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24
            ),
            artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 220),
            artworkView.heightAnchor.constraint(equalToConstant: 220),

            titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            scrubber.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            scrubber.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            scrubber.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            elapsedLabel.topAnchor.constraint(equalTo: scrubber.bottomAnchor, constant: 4),
            elapsedLabel.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),

            remainingLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),

            transport.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 28),
            transport.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            transport.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            transport.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func reload() {
        let player = AudioPlayerController.shared
        guard let track = player.currentTrack else {
            dismiss(animated: true)
            return
        }
        titleLabel.text = track.title
        if let playlist = player.playlistName, !playlist.isEmpty {
            let artist = track.subtitle
            subtitleLabel.text = artist.isEmpty ? playlist : "\(artist) · \(playlist)"
        } else {
            subtitleLabel.text = track.subtitle.isEmpty ? " " : track.subtitle
        }
        artworkView.image = player.artworkCache ?? UIImage(systemName: "music.note")
        artworkView.contentMode = player.artworkCache == nil ? .center : .scaleAspectFill
        artworkView.tintColor = .secondaryLabel

        let duration = max(player.duration, 0.1)
        if !isScrubbing {
            scrubber.minimumValue = 0
            scrubber.maximumValue = Float(duration)
            scrubber.value = Float(player.currentTime)
        }
        elapsedLabel.text = format(player.currentTime)
        remainingLabel.text = "-" + format(max(0, duration - player.currentTime))

        let symbol = player.isPlaying ? "pause.fill" : "play.fill"
        let large = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        playButton.setImage(UIImage(systemName: symbol, withConfiguration: large), for: .normal)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func libraryTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onOpenLibrary?()
        }
    }
    @objc private func playTapped() { AudioPlayerController.shared.togglePlayPause() }
    @objc private func prevTapped() { AudioPlayerController.shared.playPrevious() }
    @objc private func nextTapped() { AudioPlayerController.shared.playNext() }
    @objc private func scrubBegan() { isScrubbing = true }
    @objc private func scrubChanged() {
        elapsedLabel.text = format(TimeInterval(scrubber.value))
    }
    @objc private func scrubEnded() {
        isScrubbing = false
        AudioPlayerController.shared.seek(to: TimeInterval(scrubber.value))
    }
}
