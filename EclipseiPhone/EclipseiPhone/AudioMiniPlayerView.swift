//
//  AudioMiniPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Compact footer chrome for ambient music on the home screen.
final class AudioMiniPlayerView: UIView {

    /// Preferred height when visible.
    static let preferredHeight: CGFloat = 64

    var onOpenLibrary: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onSkipNext: (() -> Void)?
    var onToggleMute: (() -> Void)?

    private let artworkView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 6
        view.backgroundColor = UIColor(white: 0.2, alpha: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let playButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        return button
    }()

    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.setImage(UIImage(systemName: "forward.fill", withConfiguration: config),
                        for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .label
        return button
    }()

    private let muteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Refreshes labels/controls from `AudioPlayerController`.
    func reload() {
        let player = AudioPlayerController.shared
        guard let track = player.currentTrack else {
            isHidden = true
            return
        }
        isHidden = false
        titleLabel.text = track.title
        if let playlist = player.playlistName, !playlist.isEmpty {
            let artist = track.subtitle
            subtitleLabel.text = artist.isEmpty ? playlist : "\(artist) · \(playlist)"
        } else {
            subtitleLabel.text = track.subtitle.isEmpty ? "Music" : track.subtitle
        }
        artworkView.image = player.artworkCache
            ?? UIImage(systemName: "music.note")
        artworkView.tintColor = .secondaryLabel
        artworkView.contentMode = player.artworkCache == nil ? .center : .scaleAspectFill

        let playSymbol = player.isPlaying ? "pause.fill" : "play.fill"
        let playConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        playButton.setImage(
            UIImage(systemName: playSymbol, withConfiguration: playConfig), for: .normal
        )
        let muteSymbol = player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let muteConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        muteButton.setImage(
            UIImage(systemName: muteSymbol, withConfiguration: muteConfig), for: .normal
        )
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.shadowRadius = 4

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(artworkView)
        addSubview(textStack)
        addSubview(muteButton)
        addSubview(playButton)
        addSubview(nextButton)

        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 44),
            artworkView.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor,
                                               constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: muteButton.leadingAnchor,
                                                constant: -8),

            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 44),
            nextButton.heightAnchor.constraint(equalToConstant: 44),

            playButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor,
                                                 constant: -2),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),

            muteButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor,
                                                 constant: -2),
            muteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 44),
            muteButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        playButton.accessibilityLabel = "Play/Pause"
        nextButton.accessibilityLabel = "Next"
        muteButton.accessibilityLabel = "Mute"
        accessibilityLabel = "Now Playing"
        accessibilityHint = "Double tap to open Now Playing"

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        addGestureRecognizer(tap)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
    }

    @objc private func openTapped() { onOpenLibrary?() }
    @objc private func playTapped() { onTogglePlayPause?() }
    @objc private func nextTapped() { onSkipNext?() }
    @objc private func muteTapped() { onToggleMute?() }
}
