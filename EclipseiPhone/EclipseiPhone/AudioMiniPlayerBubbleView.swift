//
//  AudioMiniPlayerBubbleView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Persistent Music control: idle tap opens Music, active tap expands, long-press stops.
final class AudioMiniPlayerBubbleView: UIButton {

    static let side: CGFloat = 72
    /// Pressed-in scale while idle so opening Music still feels like a control.
    static let idlePressScale: CGFloat = 0.9

    var onExpand: (() -> Void)?
    var onStop: (() -> Void)?

    private let waveformView = AudioMiniPlayerWaveformView()
    private let rippleLayer = CAShapeLayer()
    private let rippleLayerDelayed = CAShapeLayer()
    private var isPulsing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates chrome from the shared player.
    func reload() {
        let player = AudioPlayerController.shared
        let active = player.hasActiveSession
        let playing = active && player.isPlaying
        applyPlaybackChrome(playing: playing)
        accessibilityTraits = .button
        accessibilityLabel = "Music"
        if active {
            accessibilityValue = playing ? "Playing" : "Paused"
            accessibilityHint = "Double tap to expand. Long press to stop."
        } else {
            accessibilityValue = nil
            accessibilityHint = "Opens the Music page."
        }
        applyIdlePressReaction(highlighted: isHighlighted)
    }

    /// Playing: waveform + glow. Idle / paused: music note, no glow.
    func applyPlaybackChrome(playing: Bool) {
        configuration = Self.musicConfiguration(showsNote: !playing)
        waveformView.setPlaying(playing)
        setPulsing(playing)
        applyShadow(playing: playing)
    }

    var showsPlaybackWaveform: Bool { waveformView.isPlaying && !waveformView.isHidden }
    var isPlaybackGlowActive: Bool { isPulsing }

    override var isHighlighted: Bool {
        get { super.isHighlighted }
        set {
            super.isHighlighted = newValue
            applyIdlePressReaction(highlighted: newValue)
        }
    }

    // MARK: - Private

    private func setup() {
        clipsToBounds = false
        applyShadow(playing: false)

        configureRipple(rippleLayer)
        configureRipple(rippleLayerDelayed)
        layer.insertSublayer(rippleLayer, at: 0)
        layer.insertSublayer(rippleLayerDelayed, at: 0)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true
        addSubview(waveformView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            waveformView.centerXAnchor.constraint(equalTo: centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 34),
            waveformView.heightAnchor.constraint(equalToConstant: 30)
        ])

        addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(stopPressed(_:)))
        hold.minimumPressDuration = 0.45
        addGestureRecognizer(hold)
        reload()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bringSubviewToFront(waveformView)
        let path = UIBezierPath(ovalIn: bounds).cgPath
        rippleLayer.path = path
        rippleLayer.frame = bounds
        rippleLayerDelayed.path = path
        rippleLayerDelayed.frame = bounds
        layer.shadowPath = path
    }

    private func configureRipple(_ layer: CAShapeLayer) {
        layer.fillColor = UIColor.white.withAlphaComponent(0.65).cgColor
        layer.opacity = 0
    }

    private static func musicConfiguration(showsNote: Bool) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        if showsNote {
            config.image = UIImage(
                systemName: "music.note",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
            )
        }
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .systemBlue
        config.cornerStyle = .capsule
        return config
    }

    /// Native fill already dims; idle also scales so a no-track tap still reads as a press.
    private func applyIdlePressReaction(highlighted: Bool) {
        guard !AudioPlayerController.shared.hasActiveSession else { return }
        let scale: CGFloat = highlighted ? Self.idlePressScale : 1
        let animations = {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
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
        if playing {
            layer.shadowColor = UIColor.systemBlue.cgColor
            layer.shadowOpacity = 0.95
            layer.shadowRadius = 22
            layer.shadowOffset = .zero
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }
    }

    private func setPulsing(_ pulsing: Bool) {
        guard pulsing != isPulsing else { return }
        isPulsing = pulsing
        rippleLayer.removeAnimation(forKey: "ripple")
        rippleLayerDelayed.removeAnimation(forKey: "ripple")
        rippleLayer.transform = CATransform3DIdentity
        rippleLayerDelayed.transform = CATransform3DIdentity
        guard pulsing else {
            rippleLayer.opacity = 0
            rippleLayerDelayed.opacity = 0
            return
        }
        if UIAccessibility.isReduceMotionEnabled {
            rippleLayer.transform = CATransform3DMakeScale(1.32, 1.32, 1)
            rippleLayer.opacity = 0.7
            rippleLayerDelayed.opacity = 0
            return
        }
        rippleLayer.add(Self.rippleAnimation(phase: 0), forKey: "ripple")
        rippleLayerDelayed.add(Self.rippleAnimation(phase: 0.7), forKey: "ripple")
    }

    private static func rippleAnimation(phase: CFTimeInterval) -> CAAnimation {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.72
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.4
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.timeOffset = phase
        return group
    }

    @objc private func expandTapped() {
        if !AudioPlayerController.shared.hasActiveSession {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onExpand?()
    }

    @objc private func stopPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onStop?()
    }
}
