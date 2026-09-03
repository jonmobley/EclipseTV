//
//  AudioMiniPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Compact footer chrome for ambient music on the home screen.
/// Stop lives on the Music circle, not this bar.
final class AudioMiniPlayerView: UIView, UIGestureRecognizerDelegate {

    /// Preferred height when visible.
    static let preferredHeight: CGFloat = 64
    /// Solid fill under the chrome, including the home-indicator band in portrait.
    static let barBackgroundColor: UIColor = .secondarySystemBackground
    /// Floating card width — title, speaker, and collapse control.
    static let compactWidth: CGFloat = 360
    static let compactCornerRadius: CGFloat = 20
    /// Matches the Music bubble so the bar grows from the same corner.
    static let compactTrailingInset: CGFloat = 16
    /// Gap from the screen bottom (not the safe area) so the circle sits in the corner.
    static let compactBottomInset: CGFloat = 10
    /// Space between the compact card and the Music circle.
    static let circleFooterGap: CGFloat = 8
    /// Padding around the round volume and close controls inside the 64pt bar.
    static let controlChromeInset: CGFloat = 4
    /// Round volume and close controls; same size, filling the bar height.
    static let controlSide: CGFloat = preferredHeight - controlChromeInset * 2
    /// Gap between the volume and close circles.
    static let controlGap: CGFloat = 6
    /// Trailing inset for close when the circle sits beside the card.
    static let controlTrailingInset: CGFloat = controlChromeInset

    /// Round filled chrome shared by volume and close.
    static func roundControlConfiguration(
        systemName: String,
        pointSize: CGFloat = 20
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: pointSize, weight: .bold
            )
        )
        config.baseForegroundColor = .secondaryLabel
        config.background.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        config.background.cornerRadius = controlSide / 2
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 16, leading: 16, bottom: 16, trailing: 16
        )
        return config
    }

    /// Compact trailing card in phone landscape and on regular-width layouts (iPad).
    /// Phone portrait stays a full-width footer.
    static func usesCompactCard(
        verticalSizeClass: UIUserInterfaceSizeClass,
        horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> Bool {
        verticalSizeClass == .compact || horizontalSizeClass == .regular
    }

    /// Full-width footer height. Portrait adds the home-indicator inset so tiles
    /// cannot show under the bar; the compact card stays `preferredHeight`.
    static func barHeight(floating: Bool, safeAreaBottom: CGFloat) -> CGFloat {
        preferredHeight + (floating ? 0 : max(0, safeAreaBottom))
    }

    /// Portrait overlays the circle; the compact card sits beside it.
    static func minimizeTrailingInset(floating: Bool) -> CGFloat {
        if floating { return controlTrailingInset }
        return AudioMiniPlayerBubbleView.side + circleFooterGap + compactTrailingInset
    }

    var onOpenLibrary: (() -> Void)?
    /// Collapses the bar to the floating bubble (does not stop playback).
    var onMinimize: (() -> Void)?

    /// True while the vertical volume slider is showing above the speaker.
    var isVolumeExpanded: Bool { volumeControl.isExpanded }

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

    private let volumeControl = AudioMiniVolumeControl()

    private let minimizeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        return button
    }()

    private var minimizeTrailingConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Footer edge-shadow vs. a floating card.
    func applyFloatingChrome(_ floating: Bool) {
        layer.cornerCurve = .continuous
        if floating {
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 4)
        } else {
            layer.shadowOpacity = 0.12
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: -1)
        }
        minimizeTrailingConstraint?.constant = -Self.minimizeTrailingInset(
            floating: floating
        )
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

        volumeControl.setVolume(player.isMuted ? 0 : player.volume)
    }

    /// Hides the vertical volume slider without changing the mix level.
    func collapseVolumeControl(animated: Bool = false) {
        volumeControl.setExpanded(false, animated: animated)
    }

    // MARK: - Private

    private func setup() {
        isOpaque = true
        backgroundColor = Self.barBackgroundColor
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        configureMinimizeButton()
        volumeControl.translatesAutoresizingMaskIntoConstraints = false
        volumeControl.onVolumeChange = { value, notify in
            AudioPlayerController.shared.setVolume(value, notify: notify)
        }

        addSubview(textStack)
        addSubview(volumeControl)
        addSubview(minimizeButton)
        pinChrome(textStack: textStack)
        applyFloatingChrome(false)

        accessibilityLabel = "Now Playing"
        accessibilityHint = "Double tap to open Now Playing"

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        minimizeButton.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)
    }

    private func pinChrome(textStack: UIStackView) {
        let minimizeTrailing = minimizeButton.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -Self.controlTrailingInset
        )
        minimizeTrailingConstraint = minimizeTrailing
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(
                equalTo: safeAreaLayoutGuide.centerYAnchor
            ),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: volumeControl.leadingAnchor, constant: -8
            ),

            minimizeTrailing,
            minimizeButton.topAnchor.constraint(
                equalTo: topAnchor, constant: Self.controlChromeInset
            ),
            minimizeButton.widthAnchor.constraint(equalToConstant: Self.controlSide),
            minimizeButton.heightAnchor.constraint(equalToConstant: Self.controlSide),

            volumeControl.trailingAnchor.constraint(
                equalTo: minimizeButton.leadingAnchor, constant: -Self.controlGap
            ),
            volumeControl.topAnchor.constraint(
                equalTo: topAnchor, constant: Self.controlChromeInset
            )
        ])
    }

    private func configureMinimizeButton() {
        minimizeButton.configuration = Self.roundControlConfiguration(systemName: "xmark")
        minimizeButton.accessibilityLabel = "Close"
        minimizeButton.accessibilityHint =
            "Collapse to a floating button. Music keeps playing."
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        guard volumeControl.isExpanded else { return false }
        return volumeControl.point(inside: convert(point, to: volumeControl), with: event)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let view = touch.view else { return true }
        if view is UIControl { return false }
        return !view.isDescendant(of: volumeControl)
    }

    @objc private func openTapped() {
        if volumeControl.isExpanded {
            volumeControl.setExpanded(false, animated: true)
            return
        }
        onOpenLibrary?()
    }

    @objc private func minimizeTapped() { onMinimize?() }
}
