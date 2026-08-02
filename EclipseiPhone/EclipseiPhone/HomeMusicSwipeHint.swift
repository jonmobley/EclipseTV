//
//  HomeMusicSwipeHint.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Floating Home tip for the Music page. Eligible after the first mini-player collapse.
final class HomeMusicSwipeHint: UIView {

    static let dismissedKey = "EclipseTV.home.musicSwipeHintDismissed"
    static let eligibleKey = "EclipseTV.home.musicSwipeHintEligible"

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemChromeMaterialDark)
    )
    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()
    private let dismissButton = UIButton(type: .system)
    private var musicPagingAvailable = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        blurView.layer.cornerRadius = 22
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        iconBackground.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.45)
        iconBackground.layer.cornerRadius = 10
        iconBackground.layer.cornerCurve = .continuous
        iconBackground.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = UIImage(
            systemName: "music.note",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(iconView)

        titleLabel.text = "Music"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        subtitleLabel.text = "Swipe left to open"
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        var dismissConfig = UIButton.Configuration.plain()
        dismissConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        dismissConfig.baseForegroundColor = .secondaryLabel
        dismissConfig.background.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        dismissConfig.background.cornerRadius = 12
        dismissConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 7, bottom: 7, trailing: 7
        )
        dismissButton.configuration = dismissConfig
        dismissButton.accessibilityLabel = "Dismiss"
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        addSubview(iconBackground)
        addSubview(textStack)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 68),

            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 40),
            iconBackground.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            textStack.leadingAnchor.constraint(
                equalTo: iconBackground.trailingAnchor, constant: 12
            ),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),

            dismissButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10
            ),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 28),
            dismissButton.heightAnchor.constraint(equalToConstant: 28)
        ])
        isAccessibilityElement = false
        accessibilityElements = [titleLabel, subtitleLabel, dismissButton]
    }

    /// Compact paging can swipe to Music; side-by-side layout cannot.
    ///
    /// Does not change visibility — call `reload()` from the Home host after updating.
    func setMusicPagingAvailable(_ available: Bool) {
        musicPagingAvailable = available
    }

    /// Marks the hint eligible after the first collapse / stop of the mini player.
    static func markEligibleAfterMiniPlayerClose() {
        guard !UserDefaults.standard.bool(forKey: eligibleKey) else { return }
        UserDefaults.standard.set(true, forKey: eligibleKey)
    }

    /// Permanently hides the hint (X or first Music visit).
    func dismissPermanently() {
        guard !UserDefaults.standard.bool(forKey: Self.dismissedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        reload()
    }

    /// Refreshes visibility from UserDefaults and active audio session.
    func reload() {
        let defaults = UserDefaults.standard
        let eligible = defaults.bool(forKey: Self.eligibleKey)
        let dismissed = defaults.bool(forKey: Self.dismissedKey)
        let sessionActive = AudioPlayerController.shared.hasActiveSession
        // Hide while music chrome is up so the tip doesn’t compete with the bubble.
        isHidden = !eligible || dismissed || sessionActive
        subtitleLabel.text = musicPagingAvailable
            ? "Swipe left to open"
            : "Open from the Home menu"
    }

    @objc private func dismissTapped() {
        dismissPermanently()
    }
}
