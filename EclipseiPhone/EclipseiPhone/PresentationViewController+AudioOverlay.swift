//
//  PresentationViewController+AudioOverlay.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Ambient Now Playing Chrome

extension PresentationViewController {

    /// Installs the corner badge used while ambient music plays under visuals.
    func setupAudioNowPlayingOverlay() {
        guard audioNowPlayingBadge == nil else { return }

        let badge = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = 14
        badge.clipsToBounds = true
        badge.isHidden = true
        badge.applyReduceTransparencyFallback(opaqueFill: UIColor(white: 0.12, alpha: 1))

        let icon = UIImageView(image: UIImage(systemName: "music.note"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        audioNowPlayingLabel = label

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        badge.contentView.addSubview(stack)

        view.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28
            ),
            badge.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28
            ),
            stack.topAnchor.constraint(equalTo: badge.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(
                equalTo: badge.contentView.bottomAnchor, constant: -12
            ),
            stack.leadingAnchor.constraint(
                equalTo: badge.contentView.leadingAnchor, constant: 16
            ),
            stack.trailingAnchor.constraint(
                equalTo: badge.contentView.trailingAnchor, constant: -16
            ),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22)
        ])
        audioNowPlayingBadge = badge

        audioPlayerObserver = NotificationCenter.default.addObserver(
            forName: AudioPlayerController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAudioNowPlayingOverlay()
        }
        refreshAudioNowPlayingOverlay()
    }

    /// Updates overlay visibility from the ambient player + current source.
    func refreshAudioNowPlayingOverlay() {
        guard let badge = audioNowPlayingBadge else { return }
        let player = AudioPlayerController.shared
        guard player.hasActiveSession, player.isPlaying, !isPresentingVideo else {
            badge.isHidden = true
            return
        }
        audioNowPlayingLabel?.text = player.currentTrack?.title ?? "Music"
        badge.isHidden = false
    }
}
