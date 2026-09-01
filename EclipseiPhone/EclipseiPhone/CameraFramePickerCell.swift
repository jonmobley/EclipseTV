//
//  CameraFramePickerCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Thumbnail in the Camera Frames drawer (imported frame or Add placeholder).
final class CameraFramePickerCell: UICollectionViewCell {

    static let reuseId = "CameraFramePickerCell"

    private static let moreButtonVisualSide: CGFloat = 28
    private static let moreButtonHitSide: CGFloat = 44

    private let imageView = UIImageView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    /// Full-card pull-down host used by the Add tile.
    private let menuButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        imageView.layer.cornerRadius = 10
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        imageView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        installMoreButton()
        installMenuButton()

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            iconView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 18),
            imageView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setMoreMenu(nil)
        setPrimaryMenu(nil)
        accessibilityHint = nil
        titleLabel.textColor = .label
        iconView.tintColor = .white
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
    }

    // MARK: - Configure

    /// Imported frame thumb. Caption stays blank so only Add is labeled.
    func configureFrame(image: UIImage?, selected: Bool, moreMenu: UIMenu?) {
        titleLabel.text = nil
        titleLabel.isHidden = false
        titleLabel.textColor = .label
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        iconView.image = nil
        iconView.isHidden = true
        imageView.layer.borderWidth = selected ? 3 : 0
        imageView.layer.borderColor = UIColor.systemBlue.cgColor
        setPrimaryMenu(nil)
        setMoreMenu(moreMenu)
        accessibilityLabel = selected ? "Frame, on ribbon" : "Frame"
        accessibilityHint = "Double tap to pin or unpin on the camera ribbon."
        isAccessibilityElement = true
    }

    /// Soft Add placeholder matching Show add tiles (`photo.badge.plus` + “Add”).
    func configureAdd(menu: UIMenu?) {
        titleLabel.text = "Add"
        titleLabel.isHidden = false
        titleLabel.textColor = .systemBlue
        imageView.image = nil
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .tertiarySystemFill
        imageView.layer.borderWidth = 0
        let symbol = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iconView.image = UIImage(systemName: "photo.badge.plus", withConfiguration: symbol)
        iconView.tintColor = .systemBlue
        iconView.isHidden = false
        setMoreMenu(nil)
        setPrimaryMenu(menu, accessibilityLabel: "Add")
    }

    // MARK: - More (ellipsis)

    private func installMoreButton() {
        let inset = (Self.moreButtonHitSide - Self.moreButtonVisualSide) / 2
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        config.background.cornerRadius = Self.moreButtonVisualSide / 2
        config.background.backgroundInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        config.contentInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        moreButton.configuration = config
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "More"
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.isHidden = true
        // On imageView so the pill sits on the thumb, not the caption.
        imageView.addSubview(moreButton)
        NSLayoutConstraint.activate([
            moreButton.trailingAnchor.constraint(
                equalTo: imageView.trailingAnchor, constant: -8 + inset
            ),
            moreButton.topAnchor.constraint(
                equalTo: imageView.topAnchor, constant: 8 - inset
            ),
            moreButton.widthAnchor.constraint(equalToConstant: Self.moreButtonHitSide),
            moreButton.heightAnchor.constraint(equalToConstant: Self.moreButtonHitSide)
        ])
    }

    private func setMoreMenu(_ menu: UIMenu?) {
        moreButton.menu = menu
        moreButton.isHidden = menu == nil
        if menu != nil {
            imageView.bringSubviewToFront(moreButton)
        }
    }

    // MARK: - Add pull-down

    private func installMenuButton() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.isHidden = true
        contentView.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            menuButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    private func setPrimaryMenu(_ menu: UIMenu?, accessibilityLabel: String? = nil) {
        menuButton.menu = menu
        menuButton.isHidden = menu == nil
        guard menu != nil else {
            menuButton.isAccessibilityElement = false
            return
        }
        isAccessibilityElement = false
        menuButton.isAccessibilityElement = true
        menuButton.accessibilityLabel = accessibilityLabel ?? "Add"
        contentView.bringSubviewToFront(menuButton)
    }
}
