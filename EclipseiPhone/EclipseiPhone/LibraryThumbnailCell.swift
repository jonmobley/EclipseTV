//
//  LibraryThumbnailCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LibraryThumbnailCell.swift
import UIKit

/// Grid cell showing a single Apple TV library item: thumbnail, video badge,
/// optional duration, and a highlight when the item is currently live.
final class LibraryThumbnailCell: UICollectionViewCell {

    static let reuseIdentifier = "LibraryThumbnailCell"

    // MARK: - Subviews

    private let imageView = UIImageView()
    private let placeholderIcon = UIImageView()
    private let videoBadge = UIImageView()
    private let durationLabel = PaddedLabel()
    private let liveBadge = PaddedLabel()
    private let unavailableBadge = PaddedLabel()

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
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholderIcon)

        let badgeConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)
        videoBadge.image = UIImage(systemName: "play.circle.fill", withConfiguration: badgeConfig)
        videoBadge.tintColor = UIColor.white.withAlphaComponent(0.95)
        videoBadge.translatesAutoresizingMaskIntoConstraints = false
        videoBadge.isHidden = true
        contentView.addSubview(videoBadge)

        configurePill(durationLabel, background: UIColor.black.withAlphaComponent(0.6), textColor: .white)
        durationLabel.isHidden = true
        contentView.addSubview(durationLabel)

        configurePill(liveBadge, background: .systemRed, textColor: .white)
        liveBadge.text = "LIVE"
        liveBadge.isHidden = true
        contentView.addSubview(liveBadge)

        configurePill(unavailableBadge, background: UIColor.black.withAlphaComponent(0.7), textColor: .white)
        unavailableBadge.text = "Unavailable"
        unavailableBadge.isHidden = true
        contentView.addSubview(unavailableBadge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 36),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 36),

            videoBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videoBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            liveBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            liveBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),

            unavailableBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            unavailableBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    private func configurePill(_ label: PaddedLabel, background: UIColor, textColor: UIColor) {
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = textColor
        label.backgroundColor = background
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Configuration

    func configure(with item: LibraryItemDTO, thumbnail: UIImage?, isLive: Bool) {
        // nil or true means available; only an explicit false marks a purged item.
        let isUnavailable = (item.isAvailable == false)

        imageView.image = thumbnail
        imageView.alpha = isUnavailable ? 0.35 : 1.0
        placeholderIcon.isHidden = thumbnail != nil
        placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")

        // Suppress the play/duration/live affordances for purged items; they can't play.
        videoBadge.isHidden = isUnavailable || !(item.isVideo && thumbnail != nil)

        if !isUnavailable, item.isVideo, item.duration > 0 {
            durationLabel.text = Self.formatDuration(item.duration)
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        unavailableBadge.isHidden = !isUnavailable

        let showLive = isLive && !isUnavailable
        liveBadge.isHidden = !showLive
        contentView.layer.borderWidth = showLive ? 3 : 0
        contentView.layer.borderColor = showLive ? UIColor.systemRed.cgColor : UIColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        imageView.alpha = 1.0
        placeholderIcon.isHidden = false
        videoBadge.isHidden = true
        durationLabel.isHidden = true
        liveBadge.isHidden = true
        unavailableBadge.isHidden = true
        contentView.layer.borderWidth = 0
    }

    // MARK: - Helpers

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A label with internal padding, used for the duration and live pills.
final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
