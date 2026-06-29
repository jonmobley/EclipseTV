//
//  AlbumThumbnailCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// AlbumThumbnailCell.swift
import UIKit

/// Grid cell for a remote album item. Loads its thumbnail asynchronously from the item's
/// HTTPS URL (images only; videos show a film placeholder) and cancels the in-flight load
/// on reuse.
final class AlbumThumbnailCell: UICollectionViewCell {

    static let reuseIdentifier = "AlbumThumbnailCell"

    private let imageView = UIImageView()
    private let placeholderIcon = UIImageView()
    private let videoBadge = UIImageView()
    private let nameLabel = PaddedLabel()

    /// Identifies which item the cell is currently loading, so a late completion for a
    /// recycled cell is ignored.
    private var loadToken: RemoteImageRequest?

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

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        nameLabel.layer.cornerRadius = 6
        nameLabel.layer.masksToBounds = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

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

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    // MARK: - Configuration

    func configure(with item: AlbumManifestItem, cellSize: CGSize) {
        nameLabel.text = item.resolvedName
        nameLabel.isHidden = item.resolvedName.isEmpty
        videoBadge.isHidden = !item.isVideo
        placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")
        placeholderIcon.isHidden = false
        imageView.image = nil

        // Prefer the server thumbnail (covers videos too); fall back to the placeholder
        // when there's no usable thumbnail URL.
        guard let url = item.gridThumbnailURL else { return }

        loadToken = RemoteImageLoader.shared.loadImage(from: url, targetSize: cellSize) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.imageView.image = image
            self.placeholderIcon.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken?.cancel()
        loadToken = nil
        imageView.image = nil
        placeholderIcon.isHidden = false
        videoBadge.isHidden = true
        nameLabel.isHidden = true
    }
}
