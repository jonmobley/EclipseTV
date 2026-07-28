//
//  LibraryThumbnailCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LibraryThumbnailCell.swift
import UIKit

/// Grid cell for home-library media or special tiles (Black, Camera, Web, Album).
final class LibraryThumbnailCell: UICollectionViewCell {

    static let reuseIdentifier = "LibraryThumbnailCell"

    // MARK: - Subviews

    let imageView = UIImageView()
    let placeholderIcon = UIImageView()
    let captionLabel = UILabel()
    private let videoBadge = UIImageView()
    private let durationLabel = PaddedLabel()
    let liveBadge = PaddedLabel()
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

        captionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        captionLabel.textColor = .white
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        captionLabel.isHidden = true
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(captionLabel)

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
            placeholderIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 36),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 36),

            captionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            captionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

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
        resetChrome()
        contentView.backgroundColor = .secondarySystemBackground

        // nil or true means available; only an explicit false marks a purged item.
        let isUnavailable = (item.isAvailable == false)

        imageView.image = thumbnail
        imageView.alpha = isUnavailable ? 0.35 : 1.0
        placeholderIcon.isHidden = thumbnail != nil
        placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")
        placeholderIcon.tintColor = .tertiaryLabel

        // Suppress the play/duration/live affordances for purged items; they can't play.
        videoBadge.isHidden = isUnavailable || !(item.isVideo && thumbnail != nil)

        if !isUnavailable, item.isVideo, item.duration > 0 {
            durationLabel.text = Self.formatDuration(item.duration)
            durationLabel.isHidden = false
        }

        unavailableBadge.isHidden = !isUnavailable
        setLive(isLive && !isUnavailable)
        var a11y = item.name
        if item.isVideo { a11y += ", video" }
        if isUnavailable { a11y += ", unavailable" }
        if isLive && !isUnavailable { a11y += ", live" }
        accessibilityLabel = a11y
        isAccessibilityElement = true
    }

    /// Dashed-style action tile (New Show / Add media).
    func configureActionTile(title: String, systemImage: String = "plus") {
        resetChrome()
        contentView.backgroundColor = UIColor.secondarySystemBackground
        contentView.layer.borderWidth = 1.5
        contentView.layer.borderColor = UIColor.separator.cgColor
        placeholderIcon.image = UIImage(systemName: systemImage)
        placeholderIcon.tintColor = .secondaryLabel
        placeholderIcon.isHidden = false
        captionLabel.text = title
        captionLabel.textColor = .secondaryLabel
        captionLabel.isHidden = false
        accessibilityLabel = title
        isAccessibilityElement = true
    }

    /// Configures a non-media home tile (Logo, Camera, Show, Website).
    /// - Parameter outlined: When true, draws a light stroke so a dark fill doesn't
    ///   disappear into the grid background.
    /// - Parameter thumbnailContentMode: `.scaleAspectFit` suits favicons; fill for snapshots.
    func configureSpecial(
        title: String,
        systemImage: String?,
        thumbnail: UIImage?,
        fillColor: UIColor,
        isLive: Bool,
        outlined: Bool = false,
        thumbnailContentMode: UIView.ContentMode = .scaleAspectFill
    ) {
        resetChrome()
        contentView.backgroundColor = fillColor
        imageView.contentMode = thumbnailContentMode
        imageView.image = thumbnail
        imageView.alpha = thumbnail == nil ? 0 : 1
        if let systemImage {
            placeholderIcon.image = UIImage(systemName: systemImage)
            placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.85)
            placeholderIcon.isHidden = thumbnail != nil
        } else {
            placeholderIcon.isHidden = true
        }
        captionLabel.text = title
        captionLabel.textColor = .white
        captionLabel.isHidden = false
        setLive(isLive)
        if outlined && !isLive {
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = UIColor.separator.cgColor
        }
        accessibilityLabel = isLive ? "\(title), live" : title
        isAccessibilityElement = true
    }

    func resetChrome() {
        imageView.image = nil
        imageView.alpha = 1.0
        imageView.contentMode = .scaleAspectFill
        placeholderIcon.isHidden = false
        captionLabel.isHidden = true
        captionLabel.text = nil
        captionLabel.textColor = .white
        hideMediaBadges()
        liveBadge.isHidden = true
        contentView.layer.borderWidth = 0
    }

    /// Clears play/duration/unavailable chrome used only by media cells.
    func hideMediaBadges() {
        videoBadge.isHidden = true
        durationLabel.isHidden = true
        unavailableBadge.isHidden = true
    }

    func setLive(_ isLive: Bool) {
        liveBadge.isHidden = !isLive
        contentView.layer.borderWidth = isLive ? 3 : 0
        contentView.layer.borderColor = isLive ? UIColor.systemRed.cgColor : UIColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetChrome()
        contentView.backgroundColor = .secondarySystemBackground
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
