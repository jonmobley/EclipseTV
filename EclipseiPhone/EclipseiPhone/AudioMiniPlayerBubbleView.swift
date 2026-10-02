//
//  AudioMiniPlayerBubbleView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Persistent Music control. Compact: idle opens a picker; a session shows or
/// hides the card. Regular: always toggles the Music drawer.
final class AudioMiniPlayerBubbleView: UIView {

    /// Matches the mini-player card so the two share one height.
    static let side: CGFloat = AudioMiniPlayerView.preferredHeight
    /// Pressed-in scale while idle so opening Music still feels like a control.
    static let idlePressScale: CGFloat = 0.9

    /// Compact: picker, or show / hide the card. Regular: Music drawer toggle.
    var onToggle: (() -> Void)?

    private let musicCircle = HighlightForwardingButton(type: .system)
    /// Circle control: picker, expand, stop, or drawer toggle.
    var musicButton: UIButton { musicCircle }
    private let waveformView = AudioMiniPlayerWaveformView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates chrome from the shared player.
    /// - Parameter barExpanded: Card is showing; VoiceOver says hide.
    /// - Parameter togglesMusicPane: Regular-width drawer mode (no card).
    func reload(barExpanded: Bool = false, togglesMusicPane: Bool = false) {
        let player = AudioPlayerController.shared
        applySessionChrome(
            active: player.hasActiveSession,
            playing: player.hasActiveSession && player.isPlaying,
            expanded: barExpanded,
            togglesMusicPane: togglesMusicPane
        )
        applyIdlePressReaction(highlighted: musicButton.isHighlighted)
    }

    /// Playing: waveform. Otherwise: music note. The circle never becomes Stop.
    func applySessionChrome(
        active: Bool,
        playing: Bool,
        expanded: Bool = false,
        togglesMusicPane: Bool = false
    ) {
        applyPlaybackChrome(playing: playing)
        applyAccessibility(
            active: active,
            playing: playing,
            expanded: expanded,
            togglesMusicPane: togglesMusicPane
        )
    }

    /// Playing: 3-bar waveform. Otherwise: music note.
    func applyPlaybackChrome(playing: Bool) {
        musicButton.configuration = Self.musicConfiguration(showsNote: !playing)
        waveformView.setPlaying(playing)
        applyShadow(playing: playing)
    }

    var showsPlaybackWaveform: Bool { waveformView.isPlaying && !waveformView.isHidden }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    // MARK: - Private

    private func setup() {
        clipsToBounds = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        applyShadow(playing: false)
        configureMusicButton()

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true
        musicButton.addSubview(waveformView)
        addSubview(musicCircle)

        NSLayoutConstraint.activate(Self.layoutConstraints(
            in: self, music: musicCircle, wave: waveformView
        ))
        reload()
    }

    private func configureMusicButton() {
        musicCircle.translatesAutoresizingMaskIntoConstraints = false
        musicCircle.clipsToBounds = false
        musicCircle.onHighlightChange = { [weak self] highlighted in
            self?.applyIdlePressReaction(highlighted: highlighted)
        }
        musicCircle.addTarget(self, action: #selector(musicTapped), for: .touchUpInside)
    }

    private static func layoutConstraints(
        in parent: UIView,
        music: UIButton,
        wave: UIView
    ) -> [NSLayoutConstraint] {
        [
            music.topAnchor.constraint(equalTo: parent.topAnchor),
            music.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            music.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            music.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            music.widthAnchor.constraint(equalToConstant: side),
            music.heightAnchor.constraint(equalToConstant: side),
            wave.centerXAnchor.constraint(equalTo: music.centerXAnchor),
            wave.centerYAnchor.constraint(equalTo: music.centerYAnchor),
            wave.widthAnchor.constraint(equalToConstant: 28),
            wave.heightAnchor.constraint(equalToConstant: 26)
        ]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        musicButton.bringSubviewToFront(waveformView)
        musicButton.layer.shadowPath = UIBezierPath(ovalIn: musicButton.bounds).cgPath
    }

    private static func musicConfiguration(showsNote: Bool) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        if showsNote {
            config.image = UIImage(
                systemName: "music.note",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 24, weight: .semibold
                )
            )
        }
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .accent
        config.cornerStyle = .capsule
        return config
    }

    private func applyAccessibility(
        active: Bool,
        playing: Bool,
        expanded: Bool,
        togglesMusicPane: Bool
    ) {
        musicButton.accessibilityTraits = .button
        if togglesMusicPane {
            musicButton.accessibilityLabel = "Music"
            musicButton.accessibilityHint = "Shows or hides the Music pane."
            musicButton.accessibilityValue = playing ? "Playing"
                : (active ? "Paused" : nil)
            return
        }
        if active {
            musicButton.accessibilityLabel = expanded ? "Hide player" : "Show player"
            musicButton.accessibilityHint = expanded
                ? "Hides the playback bar. Music keeps playing."
                : "Shows the playback bar."
            musicButton.accessibilityValue = playing ? "Playing" : "Paused"
        } else {
            musicButton.accessibilityLabel = "Music"
            musicButton.accessibilityHint = "Choose something to play."
            musicButton.accessibilityValue = nil
        }
    }

    /// Native fill already dims; idle also scales so a no-track tap still reads as a press.
    private func applyIdlePressReaction(highlighted: Bool) {
        guard !AudioPlayerController.shared.hasActiveSession else { return }
        let scale: CGFloat = highlighted ? Self.idlePressScale : 1
        let animations = {
            self.musicButton.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        if !UIView.areAnimationsEnabled || UIAccessibility.isReduceMotionEnabled {
            animations()
            return
        }
        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: animations
        )
    }

    private func applyShadow(playing: Bool) {
        let layer = musicButton.layer
        if playing {
            layer.shadowColor = UIColor.accent.cgColor
            layer.shadowOpacity = 0.4
            layer.shadowRadius = 12
            layer.shadowOffset = .zero
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }
    }

    @objc private func musicTapped() {
        let style: UIImpactFeedbackGenerator.FeedbackStyle =
            AudioPlayerController.shared.hasActiveSession ? .medium : .light
        Haptics.impact(style)
        onToggle?()
    }
}

/// Forwards highlight so idle press scale runs from tests and touches.
private final class HighlightForwardingButton: UIButton {
    var onHighlightChange: ((Bool) -> Void)?

    override var isHighlighted: Bool {
        get { super.isHighlighted }
        set {
            super.isHighlighted = newValue
            onHighlightChange?(newValue)
        }
    }
}
