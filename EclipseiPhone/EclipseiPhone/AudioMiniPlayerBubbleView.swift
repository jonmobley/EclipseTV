//
//  AudioMiniPlayerBubbleView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Persistent Music control: idle tap opens a picker sheet; session tap expands
/// the footer. The same circle becomes Stop while the footer is showing.
final class AudioMiniPlayerBubbleView: UIView {

    static let side: CGFloat = 72
    /// Pressed-in scale while idle so opening Music still feels like a control.
    static let idlePressScale: CGFloat = 0.9

    /// Idle opens the picker; collapsed session expands; expanded session stops.
    var onToggle: (() -> Void)?

    private let musicCircle = HighlightForwardingButton(type: .system)
    /// Circle control: picker, expand, or stop depending on session and footer.
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
    /// - Parameter barExpanded: Footer is showing; this circle is Stop.
    func reload(barExpanded: Bool = false) {
        let player = AudioPlayerController.shared
        applySessionChrome(
            active: player.hasActiveSession,
            playing: player.hasActiveSession && player.isPlaying,
            expanded: barExpanded
        )
        applyIdlePressReaction(highlighted: musicButton.isHighlighted)
    }

    /// Playing: waveform. Expanded: stop. Otherwise: music note.
    func applySessionChrome(active: Bool, playing: Bool, expanded: Bool = false) {
        let showStop = active && expanded
        applyPlaybackChrome(playing: playing && !showStop, showStop: showStop)
        applyAccessibility(active: active, playing: playing, showStop: showStop)
    }

    /// Playing: 3-bar waveform. Stop: stop glyph. Otherwise: music note.
    func applyPlaybackChrome(playing: Bool, showStop: Bool = false) {
        musicButton.configuration = Self.musicConfiguration(
            showsNote: !playing && !showStop,
            showsStop: showStop
        )
        waveformView.setPlaying(playing)
        applyShadow(playing: playing || showStop)
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

    private static func musicConfiguration(
        showsNote: Bool,
        showsStop: Bool
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        if showsStop {
            config.image = UIImage(
                systemName: "stop.fill",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 22, weight: .semibold
                )
            )
        } else if showsNote {
            config.image = UIImage(
                systemName: "music.note",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 24, weight: .semibold
                )
            )
        }
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .systemBlue
        config.cornerStyle = .capsule
        return config
    }

    private func applyAccessibility(active: Bool, playing: Bool, showStop: Bool) {
        musicButton.accessibilityTraits = .button
        if showStop {
            musicButton.accessibilityLabel = "Stop"
            musicButton.accessibilityHint = "Fades out and stops playback."
            musicButton.accessibilityValue = playing ? "Playing" : "Paused"
        } else if active {
            musicButton.accessibilityLabel = "Expand"
            musicButton.accessibilityHint =
                "Shows the playback bar. Tap again to stop."
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
            layer.shadowColor = UIColor.systemBlue.cgColor
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
        UIImpactFeedbackGenerator(style: style).impactOccurred()
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
