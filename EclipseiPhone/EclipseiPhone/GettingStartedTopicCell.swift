//
//  GettingStartedTopicCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Icon badge + title + body used by the Getting Started guide.
final class GettingStartedTopicCell: UITableViewCell {

    static let reuseIdentifier = "GettingStartedTopicCell"

    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let textStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        bodyLabel.text = nil
        iconView.image = nil
        iconBackground.backgroundColor = .clear
        iconView.tintColor = .label
    }

    /// Fills the row with a colored glyph, title, and wrapping body copy.
    func configure(title: String, body: String, systemImage: String, tint: UIColor) {
        titleLabel.text = title
        bodyLabel.text = body
        iconView.image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        iconView.tintColor = tint
        iconBackground.backgroundColor = tint.withAlphaComponent(0.18)
        accessibilityLabel = "\(title). \(body)"
    }

    // MARK: - Private

    private func setup() {
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground

        iconBackground.layer.cornerRadius = 12
        iconBackground.layer.cornerCurve = .continuous
        iconBackground.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(iconView)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 6
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconBackground)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor
            ),
            iconBackground.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: 16
            ),
            iconBackground.widthAnchor.constraint(equalToConstant: 40),
            iconBackground.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),

            textStack.leadingAnchor.constraint(
                equalTo: iconBackground.trailingAnchor, constant: 14
            ),
            textStack.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor
            ),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -16
            ),

            iconBackground.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor, constant: -16
            )
        ])
        isAccessibilityElement = true
    }
}
