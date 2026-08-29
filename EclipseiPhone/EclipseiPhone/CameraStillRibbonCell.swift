//
//  CameraStillRibbonCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Thumbnail in the camera stills ribbon (Background, cutaway, or add).
final class CameraStillRibbonCell: UICollectionViewCell {
    static let reuseId = "CameraStillRibbonCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let symbolView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        contentView.addSubview(imageView)
        contentView.addSubview(symbolView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            symbolView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 22),
            symbolView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures art, red live stroke, and VoiceOver for a ribbon item.
    func configure(
        image: UIImage?,
        symbolName: String?,
        isLive: Bool,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        imageView.image = image
        imageView.isHidden = image == nil
        if let symbolName {
            let symbol = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            symbolView.image = UIImage(
                systemName: symbolName, withConfiguration: symbol
            )
        } else {
            symbolView.image = nil
        }
        symbolView.isHidden = image != nil
        contentView.backgroundColor = image == nil
            ? UIColor.black.withAlphaComponent(0.45)
            : .black
        contentView.layer.borderWidth = isLive ? 3 : 1
        contentView.layer.borderColor = isLive
            ? UIColor.systemRed.cgColor
            : UIColor.white.withAlphaComponent(0.35).cgColor
        self.accessibilityLabel = accessibilityLabel
        accessibilityValue = isLive ? "On program" : "Off"
        self.accessibilityHint = accessibilityHint
        isAccessibilityElement = true
    }
}
