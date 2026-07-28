//
//  HomeSectionHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Small title above the Recent Shows ribbon.
final class HomeSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "HomeSectionHeaderView"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sets the ribbon section title.
    func configure(title: String) {
        titleLabel.text = title
    }
}
