//
//  HomeSectionHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Section title above a home grid band; optional trailing text action (See All).
final class HomeSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "HomeSectionHeaderView"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.accessibilityTraits = .header
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitleColor(.systemBlue, for: .normal)
        button.contentHorizontalAlignment = .trailing
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var actionHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(actionButton)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            actionButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8
            ),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        actionHandler = nil
        actionButton.isHidden = true
        actionButton.setTitle(nil, for: .normal)
    }

    /// Sets the section title and optional trailing blue text action.
    func configure(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        titleLabel.text = title
        if let actionTitle, let action {
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.isHidden = false
            actionHandler = action
            actionButton.accessibilityLabel = actionTitle
                .replacingOccurrences(of: " >", with: "")
                .replacingOccurrences(of: " ›", with: "")
        } else {
            actionButton.setTitle(nil, for: .normal)
            actionButton.isHidden = true
            actionHandler = nil
        }
    }

    @objc private func actionTapped() {
        actionHandler?()
    }
}
