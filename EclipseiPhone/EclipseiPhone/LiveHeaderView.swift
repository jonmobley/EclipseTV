//
//  LiveHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LiveHeaderView.swift
import UIKit

/// Large hero banner pinned to the top of the Library screen showing whatever is
/// currently live on the Apple TV. When nothing is live it falls back to a neutral
/// placeholder so the layout stays fixed while the grid scrolls beneath it.
final class LiveHeaderView: UIView {

    // MARK: - Subviews

    private let imageView = UIImageView()
    private let placeholderIcon = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let liveBadge = PaddedLabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    /// Remote transport controls, shown only when the live item is a video.
    private let controls = PlaybackControlsView()

    /// Forwarded from the transport controls (play/pause, skip ±10s, absolute seek).
    var onTogglePlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onSeek: ((Double) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.image = UIImage(systemName: "tv")
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderIcon)

        gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.65).cgColor]
        gradientLayer.locations = [0.45, 1.0]
        layer.addSublayer(gradientLayer)

        liveBadge.font = .systemFont(ofSize: 13, weight: .bold)
        liveBadge.textColor = .white
        liveBadge.backgroundColor = .systemRed
        liveBadge.text = "LIVE"
        liveBadge.layer.cornerRadius = 6
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveBadge)

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        // No tap-to-open-options on the banner; only the transport controls are interactive.
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        controls.onTogglePlayPause = { [weak self] in self?.onTogglePlayPause?() }
        controls.onSkip = { [weak self] delta in self?.onSkip?(delta) }
        controls.onSeek = { [weak self] position in self?.onSeek?(position) }
        addSubview(controls)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 52),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 52),

            liveBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            liveBadge.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -4)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    // MARK: - Configuration

    /// Shows the live item, or a placeholder when `item` is nil (nothing live).
    func configure(with item: LibraryItemDTO?, thumbnail: UIImage?, isOnline: Bool) {
        guard let item = item else {
            showPlaceholder(isOnline: isOnline)
            return
        }

        imageView.image = thumbnail
        imageView.isHidden = false
        placeholderIcon.isHidden = thumbnail != nil
        placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")

        // Keep the live preview clean: show only the LIVE badge, not the item's title
        // or type overlay (and so no bottom gradient is needed).
        gradientLayer.isHidden = true
        liveBadge.isHidden = false
        titleLabel.isHidden = true
        subtitleLabel.isHidden = true
        isUserInteractionEnabled = true

        // Transport controls only apply to videos (and only while connected).
        controls.isHidden = !(item.isVideo && isOnline)
    }

    private func showPlaceholder(isOnline: Bool) {
        imageView.image = nil
        imageView.isHidden = true
        placeholderIcon.isHidden = false
        placeholderIcon.image = UIImage(systemName: "tv")

        gradientLayer.isHidden = true
        liveBadge.isHidden = true
        subtitleLabel.isHidden = true
        controls.isHidden = true

        titleLabel.isHidden = false
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.text = isOnline ? "Nothing live yet" : "Apple TV not connected"
        isUserInteractionEnabled = false
    }

    /// Applies the latest playback state to the transport controls.
    func updatePlayback(_ state: PlaybackState) {
        controls.update(isPlaying: state.isPlaying, currentTime: state.currentTime, duration: state.duration)
    }
}
