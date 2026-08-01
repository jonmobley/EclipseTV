//
//  AudioMiniPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Compact footer chrome for ambient music on the home screen.
final class AudioMiniPlayerView: UIView, UIGestureRecognizerDelegate {

    /// Preferred height when visible.
    static let preferredHeight: CGFloat = 64

    var onOpenLibrary: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    /// Collapses the bar to the floating bubble (does not stop playback).
    var onMinimize: (() -> Void)?

    /// Blue album tile that hosts play / pause (floating bubble keeps the note).
    private let artworkButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.clipsToBounds = true
        button.layer.cornerRadius = 8
        button.layer.cornerCurve = .continuous
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.45)
        button.tintColor = .white
        return button
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

    private let speakerIcon: UIImageView = {
        let view = UIImageView()
        view.tintColor = .secondaryLabel
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let volumeSlider = GenerousVolumeSlider()

    private let minimizeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        return button
    }()

    private var isAdjustingVolume = false

    /// Floats above the slider while dragging so the thumb doesn't cover the level.
    private let volumeHUD: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.layer.cornerRadius = 14
        view.clipsToBounds = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let volumeHUDLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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

        let playSymbol = player.isPlaying ? "pause.fill" : "play.fill"
        var art = UIButton.Configuration.filled()
        art.image = UIImage(
            systemName: playSymbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        art.baseForegroundColor = .white
        art.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.45)
        art.cornerStyle = .fixed
        art.background.cornerRadius = 8
        art.contentInsets = .zero
        artworkButton.configuration = art
        artworkButton.accessibilityLabel = player.isPlaying ? "Pause" : "Play"

        let level = player.isMuted ? 0 : player.volume
        speakerIcon.image = UIImage(
            systemName: Self.speakerSymbol(for: level),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
        if !isAdjustingVolume {
            volumeSlider.value = level
        }
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .secondarySystemBackground
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.shadowRadius = 4

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        var minimizeConfig = UIButton.Configuration.plain()
        minimizeConfig.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        )
        minimizeConfig.baseForegroundColor = .secondaryLabel
        minimizeConfig.background.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        minimizeConfig.background.cornerRadius = 22
        minimizeConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 12, leading: 12, bottom: 12, trailing: 12
        )
        minimizeButton.configuration = minimizeConfig
        minimizeButton.accessibilityLabel = "Minimize"
        minimizeButton.accessibilityHint = "Collapse to a floating button. Music keeps playing."

        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.accessibilityLabel = "Volume"
        volumeSlider.tintColor = .secondaryLabel
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        volumeSlider.addTarget(self, action: #selector(volumeBegan), for: .touchDown)
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        volumeSlider.addTarget(
            self,
            action: #selector(volumeEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        volumeHUD.contentView.addSubview(volumeHUDLabel)

        addSubview(artworkButton)
        addSubview(textStack)
        addSubview(speakerIcon)
        addSubview(volumeSlider)
        addSubview(minimizeButton)
        addSubview(volumeHUD)

        NSLayoutConstraint.activate([
            artworkButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            artworkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkButton.widthAnchor.constraint(equalToConstant: 44),
            artworkButton.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(
                equalTo: artworkButton.trailingAnchor, constant: 10
            ),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 120),

            minimizeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            minimizeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            minimizeButton.widthAnchor.constraint(equalToConstant: 44),
            minimizeButton.heightAnchor.constraint(equalToConstant: 44),

            speakerIcon.leadingAnchor.constraint(
                equalTo: textStack.trailingAnchor, constant: 10
            ),
            speakerIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            speakerIcon.widthAnchor.constraint(equalToConstant: 18),
            speakerIcon.heightAnchor.constraint(equalToConstant: 18),

            volumeSlider.leadingAnchor.constraint(
                equalTo: speakerIcon.trailingAnchor, constant: 6
            ),
            volumeSlider.trailingAnchor.constraint(
                equalTo: minimizeButton.leadingAnchor, constant: -10
            ),
            volumeSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            volumeSlider.heightAnchor.constraint(equalToConstant: 44),

            volumeHUD.centerXAnchor.constraint(equalTo: volumeSlider.centerXAnchor),
            volumeHUD.bottomAnchor.constraint(
                equalTo: volumeSlider.topAnchor, constant: -28
            ),
            volumeHUD.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            volumeHUD.heightAnchor.constraint(equalToConstant: 40),

            volumeHUDLabel.leadingAnchor.constraint(
                equalTo: volumeHUD.contentView.leadingAnchor, constant: 12
            ),
            volumeHUDLabel.trailingAnchor.constraint(
                equalTo: volumeHUD.contentView.trailingAnchor, constant: -12
            ),
            volumeHUDLabel.centerYAnchor.constraint(
                equalTo: volumeHUD.contentView.centerYAnchor
            )
        ])

        accessibilityLabel = "Now Playing"
        accessibilityHint = "Double tap to open Now Playing"

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        artworkButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        minimizeButton.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)
    }

    private static func speakerSymbol(for volume: Float) -> String {
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.4 { return "speaker.wave.1.fill" }
        if volume < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        !(touch.view is UIControl) && !(touch.view is UISlider)
    }

    @objc private func openTapped() { onOpenLibrary?() }
    @objc private func playTapped() { onTogglePlayPause?() }
    @objc private func minimizeTapped() { onMinimize?() }

    @objc private func volumeBegan() {
        isAdjustingVolume = true
        updateVolumeChrome()
        volumeHUD.alpha = 0
        volumeHUD.isHidden = false
        UIView.animate(withDuration: 0.15) { self.volumeHUD.alpha = 1 }
    }

    @objc private func volumeChanged() {
        updateVolumeChrome()
        // Live audio only — full notify on end (avoids Music-page reload flicker).
        AudioPlayerController.shared.setVolume(volumeSlider.value, notify: false)
    }

    @objc private func volumeEnded() {
        isAdjustingVolume = false
        AudioPlayerController.shared.setVolume(volumeSlider.value, notify: true)
        UIView.animate(withDuration: 0.2, delay: 0.15) {
            self.volumeHUD.alpha = 0
        } completion: { _ in
            self.volumeHUD.isHidden = true
        }
    }

    private func updateVolumeChrome() {
        let value = volumeSlider.value
        let percent = Int((value * 100).rounded())
        volumeHUDLabel.text = "\(percent)%"
        speakerIcon.image = UIImage(
            systemName: Self.speakerSymbol(for: value),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
    }
}

// MARK: - Generous hit target

/// Wider / taller touch area than the visual track so volume is easy to grab.
private final class GenerousVolumeSlider: UISlider {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expanded = CGRect(
            x: bounds.minX - 14,
            y: bounds.minY - 10,
            width: bounds.width + 14 + 4,
            height: bounds.height + 20
        )
        return expanded.contains(point)
    }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.trackRect(forBounds: bounds)
        rect.size.height = 4
        rect.origin.y = (bounds.height - rect.height) / 2
        return rect
    }
}
