//
//  AlbumFolderCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Home-grid tile for an album you can open (cover + title).
final class AlbumFolderCell: UICollectionViewCell {

    static let reuseId = "AlbumFolderCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.layer.cornerRadius = 15
        return view
    }()

    private let dimView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.layer.cornerRadius = 15
        view.clipsToBounds = true
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        label.textAlignment = .left
        label.numberOfLines = 2
        return label
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.font = UIFont.preferredFont(forTextStyle: .title3)
        return label
    }()

    private let focusRing: UIView = {
        let view = UIView()
        view.layer.borderWidth = 6
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.cornerRadius = 18
        view.isHidden = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        contentView.clipsToBounds = false
        [imageView, dimView, titleLabel, countLabel, focusRing].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            dimView.heightAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: 0.42),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            titleLabel.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -2),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            countLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            focusRing.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -4),
            focusRing.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -4),
            focusRing.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 4),
            focusRing.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        titleLabel.text = nil
        countLabel.text = nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.focusRing.isHidden = !self.isFocused
            if UIAccessibility.isReduceMotionEnabled {
                self.transform = .identity
            } else {
                self.transform = self.isFocused
                    ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            }
        }
    }

    /// Sets the album title, item count, and optional cover still.
    func configure(title: String, count: Int, cover: UIImage?) {
        titleLabel.text = title
        countLabel.text = count == 1 ? "1 item" : "\(count) items"
        setCover(cover)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(title), \(countLabel.text ?? "")"
    }

    /// Updates only the cover still after an async load.
    func setCover(_ cover: UIImage?) {
        imageView.image = cover
        imageView.backgroundColor = cover == nil
            ? UIColor(white: 0.14, alpha: 1) : .black
    }
}
