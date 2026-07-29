//
//  LibraryThumbnailCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Grid cell for home-library media or special tiles (Logo, Camera, Web, Album).
final class LibraryThumbnailCell: UICollectionViewCell {

    static let reuseIdentifier = "LibraryThumbnailCell"

    // MARK: - Subviews

    /// Rounded media / tool surface (caption may sit below this in Landscape).
    let cardView = UIView()
    let imageView = UIImageView()
    let placeholderIcon = UIImageView()
    let captionLabel = UILabel()
    /// Bottom fade under overlaid captions (Vertical tools / Show titles).
    let captionScrimView = GradientView()
    private let videoBadge = UIImageView()
    private let durationLabel = PaddedLabel()
    let liveBadge = PaddedLabel()
    private let unavailableBadge = PaddedLabel()
    /// Warm live feed for the home Camera tile (nil until first idle configure).
    var cameraPreview: CameraPreviewView?
    /// Hides the last-frame freeze once the tile preview is painting.
    var cameraFreezeRevealWorkItem: DispatchWorkItem?

    /// Active while caption is overlaid on the card (Vertical / media).
    var cardFillConstraints: [NSLayoutConstraint] = []
    /// Active while caption sits under the card (Landscape tools).
    var cardAboveCaptionConstraints: [NSLayoutConstraint] = []
    /// Tracks the last applied caption placement.
    var captionBelowCard = false

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
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false

        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 12
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(imageView)

        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(placeholderIcon)

        captionScrimView.colors = [
            UIColor.clear,
            UIColor.black.withAlphaComponent(0.72)
        ]
        captionScrimView.locations = [0, 1]
        captionScrimView.isHidden = true
        captionScrimView.isUserInteractionEnabled = false
        captionScrimView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(captionScrimView)

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
        cardView.addSubview(videoBadge)

        configurePill(durationLabel, background: UIColor.black.withAlphaComponent(0.6), textColor: .white)
        durationLabel.isHidden = true
        cardView.addSubview(durationLabel)

        configurePill(liveBadge, background: .systemRed, textColor: .white)
        liveBadge.text = "LIVE"
        liveBadge.isHidden = true
        cardView.addSubview(liveBadge)

        configurePill(unavailableBadge, background: UIColor.black.withAlphaComponent(0.7), textColor: .white)
        unavailableBadge.text = "Unavailable"
        unavailableBadge.isHidden = true
        cardView.addSubview(unavailableBadge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: cardView.centerYAnchor, constant: -10),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 36),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 36),

            captionScrimView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            captionScrimView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            captionScrimView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            captionScrimView.heightAnchor.constraint(equalTo: cardView.heightAnchor, multiplier: 0.42),

            videoBadge.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            videoBadge.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),

            durationLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            durationLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),

            liveBadge.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            liveBadge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),

            unavailableBadge.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            unavailableBadge.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8)
        ])

        applyCaptionPlacement(belowCard: false)
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
        applyCaptionPlacement(belowCard: false)
        cardView.backgroundColor = .secondarySystemBackground

        let isUnavailable = (item.isAvailable == false)

        imageView.image = thumbnail
        imageView.alpha = isUnavailable ? 0.35 : 1.0
        placeholderIcon.isHidden = thumbnail != nil
        placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")
        placeholderIcon.tintColor = .tertiaryLabel

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
        applyCaptionPlacement(belowCard: false)
        cardView.backgroundColor = UIColor.secondarySystemBackground
        cardView.layer.borderWidth = 1.5
        cardView.layer.borderColor = UIColor.separator.cgColor
        placeholderIcon.image = UIImage(systemName: systemImage)
        placeholderIcon.tintColor = .secondaryLabel
        placeholderIcon.isHidden = false
        captionLabel.text = title
        captionLabel.isHidden = false
        updateCaptionScrim()
        accessibilityLabel = title
        isAccessibilityElement = true
    }

    /// Configures a non-media home tile (Logo, Camera, Show, Website).
    /// - Parameter outlined: When true, draws a light stroke so a dark fill doesn't
    ///   disappear into the grid background.
    /// - Parameter thumbnailContentMode: `.scaleAspectFit` suits favicons; fill for snapshots.
    /// - Parameter captionBelowInLandscape: Logo / Camera / Website use under-card
    ///   labels in Landscape; Show covers keep an overlay title.
    func configureSpecial(
        title: String,
        systemImage: String?,
        thumbnail: UIImage?,
        fillColor: UIColor,
        isLive: Bool,
        outlined: Bool = false,
        thumbnailContentMode: UIView.ContentMode = .scaleAspectFill,
        captionBelowInLandscape: Bool = false
    ) {
        resetChrome()
        let below = captionBelowInLandscape && !ExternalOutputSettings.isVerticalMode
        applyCaptionPlacement(belowCard: below)
        cardView.backgroundColor = fillColor
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
        captionLabel.isHidden = false
        updateCaptionScrim()
        setLive(isLive)
        if outlined && !isLive {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor = UIColor.separator.cgColor
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
        captionScrimView.isHidden = true
        hideMediaBadges()
        liveBadge.isHidden = true
        cardView.layer.borderWidth = 0
        recycleCameraPreview()
        stopArrangeWiggle()
    }

    /// Clears play/duration/unavailable chrome used only by media cells.
    func hideMediaBadges() {
        videoBadge.isHidden = true
        durationLabel.isHidden = true
        unavailableBadge.isHidden = true
    }

    func setLive(_ isLive: Bool) {
        liveBadge.isHidden = !isLive
        cardView.layer.borderWidth = isLive ? 3 : 0
        cardView.layer.borderColor = isLive ? UIColor.systemRed.cgColor : UIColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetChrome()
        applyCaptionPlacement(belowCard: false)
        cardView.backgroundColor = .secondarySystemBackground
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

/// Vertical `CAGradientLayer` host for caption readability scrims.
final class GradientView: UIView {
    var colors: [UIColor] = [] {
        didSet { updateColors() }
    }
    var locations: [NSNumber] = [0, 1] {
        didSet { gradient.locations = locations }
    }

    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    private func updateColors() {
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = locations
    }
}
