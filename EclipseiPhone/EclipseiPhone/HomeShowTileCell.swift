//
//  HomeShowTileCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Home Recent Show tile: cover or gradient, title, relative open time, more menu.
final class HomeShowTileCell: UICollectionViewCell {

    static let reuseIdentifier = "HomeShowTileCell"

    var onMore: (() -> Void)?

    private let cardView = UIView()
    private let placeholderGradient = GradientView()
    private let imageView = UIImageView()
    private let scrimView = GradientView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let moreButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        imageView.isHidden = true
        placeholderGradient.isHidden = true
        scrimView.isHidden = true
        titleLabel.text = nil
        subtitleLabel.text = nil
        cardView.layer.borderWidth = 0
        cardView.layer.borderColor = UIColor.clear.cgColor
        moreButton.isHidden = true
        onMore = nil
        titleLabel.textColor = .label
        subtitleLabel.textColor = .secondaryLabel
        applyMoreButtonForeground(.secondaryLabel)
    }

    /// Configures a Show tile with optional cover and more menu.
    ///
    /// When `thumbnail` is nil, a stable gradient derived from `showId` fills the card.
    /// Covers always aspect-fill the square tile (crop), including landscape video posters.
    func configureShow(
        showId: UUID,
        title: String,
        subtitle: String,
        thumbnail: UIImage?,
        isLive: Bool,
        moreMenu: UIMenu?
    ) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        // Re-assert on every bind — recycled cells must never keep a fit/letterbox mode.
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        if let thumbnail {
            // Landscape video posters are wider than the square tile; crop to fill
            // so Home never shows letterbox bars above/below the cover.
            imageView.image = MediaAspect.centerCroppedToSquare(thumbnail)
            imageView.isHidden = false
            placeholderGradient.isHidden = true
            scrimView.isHidden = false
        } else {
            imageView.image = nil
            imageView.isHidden = true
            placeholderGradient.colors = ShowCoverGradient.colors(for: showId)
            placeholderGradient.isHidden = false
            scrimView.isHidden = false
        }
        titleLabel.textColor = .white
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        applyMoreButtonForeground(.white)
        cardView.layer.borderWidth = isLive ? 3 : 0
        cardView.layer.borderColor = isLive
            ? UIColor.systemRed.cgColor
            : UIColor.clear.cgColor
        moreButton.menu = moreMenu
        moreButton.isHidden = moreMenu == nil
        accessibilityLabel = isLive ? "\(title), Live. \(subtitle)" : "\(title). \(subtitle)"
    }

    /// True when the tile is still on its gradient (no cover yet).
    var isShowingPlaceholder: Bool { imageView.image == nil }

    /// Paints a late-arriving cover without rebuilding titles / more menu.
    func applyLoadedCover(_ thumbnail: UIImage) {
        guard imageView.image == nil else { return }
        imageView.image = MediaAspect.centerCroppedToSquare(thumbnail)
        imageView.isHidden = false
        placeholderGradient.isHidden = true
        scrimView.isHidden = false
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        placeholderGradient.isHidden = true
        placeholderGradient.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(placeholderGradient)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(imageView)

        scrimView.colors = [
            UIColor.clear,
            UIColor.black.withAlphaComponent(0.72)
        ]
        scrimView.locations = [0.4, 1]
        scrimView.isHidden = true
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(scrimView)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Same generous 44×44 hit / 28pt pill pattern as Show media tiles.
        let hit: CGFloat = 44
        let visual: CGFloat = 28
        let inset = (hit - visual) / 2
        var moreConfig = UIButton.Configuration.plain()
        moreConfig.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        )
        moreConfig.baseForegroundColor = .secondaryLabel
        moreConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        moreConfig.background.cornerRadius = visual / 2
        moreConfig.background.backgroundInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        moreConfig.contentInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        moreButton.configuration = moreConfig
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "More"
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.isHidden = true
        cardView.addSubview(moreButton)

        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            placeholderGradient.topAnchor.constraint(equalTo: cardView.topAnchor),
            placeholderGradient.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor
            ),
            placeholderGradient.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor
            ),
            placeholderGradient.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            scrimView.topAnchor.constraint(equalTo: cardView.topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor, constant: 14
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor, constant: -14
            ),
            titleLabel.bottomAnchor.constraint(
                equalTo: subtitleLabel.topAnchor, constant: -2
            ),

            subtitleLabel.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor, constant: 14
            ),
            subtitleLabel.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor, constant: -14
            ),
            subtitleLabel.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor, constant: -14
            ),

            // Visual pill at 8pt inset; 44pt hit target grows inward (inset = 8).
            moreButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            moreButton.topAnchor.constraint(equalTo: cardView.topAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private func applyMoreButtonForeground(_ color: UIColor) {
        guard var config = moreButton.configuration else { return }
        config.baseForegroundColor = color
        moreButton.configuration = config
    }
}
