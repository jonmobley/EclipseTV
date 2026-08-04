//
//  AudioMiniPlayerBubbleView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Collapsed ambient-music control: tap expands, long-press stops.
final class AudioMiniPlayerBubbleView: UIView {

    static let side: CGFloat = 56

    var onExpand: (() -> Void)?
    var onStop: (() -> Void)?

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterial)
    )
    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let pulseLayer = CAShapeLayer()
    private var isPulsing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates pulse / accessibility from the shared player.
    func reload() {
        let player = AudioPlayerController.shared
        guard player.hasActiveSession else {
            isHidden = true
            setPulsing(false)
            return
        }
        isHidden = false
        let playing = player.isPlaying
        // Note glyph (not play/pause) so tap reads as “expand,” not transport.
        iconView.image = UIImage(
            systemName: "music.note",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        accessibilityLabel = "Music"
        accessibilityValue = playing ? "Playing" : "Paused"
        accessibilityHint = "Double tap to expand. Long press to stop."
        setPulsing(playing)
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        blurView.layer.cornerRadius = Self.side / 2
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        iconBackground.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.45)
        iconBackground.layer.cornerRadius = (Self.side - 12) / 2
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(iconBackground)

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(iconView)

        pulseLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.35).cgColor
        pulseLayer.opacity = 0
        layer.insertSublayer(pulseLayer, at: 0)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),

            iconBackground.centerXAnchor.constraint(
                equalTo: blurView.contentView.centerXAnchor
            ),
            iconBackground.centerYAnchor.constraint(
                equalTo: blurView.contentView.centerYAnchor
            ),
            iconBackground.widthAnchor.constraint(equalToConstant: Self.side - 12),
            iconBackground.heightAnchor.constraint(equalToConstant: Self.side - 12),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button

        let tap = UITapGestureRecognizer(target: self, action: #selector(expandTapped))
        addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(stopPressed(_:)))
        hold.minimumPressDuration = 0.45
        addGestureRecognizer(hold)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = bounds.insetBy(dx: -6, dy: -6)
        pulseLayer.path = UIBezierPath(ovalIn: inset).cgPath
        pulseLayer.frame = bounds
    }

    private func setPulsing(_ pulsing: Bool) {
        guard pulsing != isPulsing else { return }
        isPulsing = pulsing
        pulseLayer.removeAnimation(forKey: "pulse")
        if pulsing {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.55
            anim.toValue = 0.05
            anim.duration = 1.1
            anim.autoreverses = true
            anim.repeatCount = .infinity
            pulseLayer.add(anim, forKey: "pulse")
            pulseLayer.opacity = 0.35
        } else {
            pulseLayer.opacity = 0
        }
    }

    @objc private func expandTapped() { onExpand?() }

    @objc private func stopPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onStop?()
    }
}
