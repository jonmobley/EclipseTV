//
//  MediaNoteCardView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Welcome-style note card without the Getting Started icon badge.
final class MediaNoteCardView: UIView {

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let textStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Fills the card. Empty `note` shows the tap-to-add placeholder.
    func configure(note: String?) {
        titleLabel.text = "Note"
        if let note, !note.isEmpty {
            bodyLabel.text = note
            bodyLabel.textColor = .secondaryLabel
            accessibilityLabel = "Note. \(note)"
        } else {
            bodyLabel.text = "Tap to add a note"
            bodyLabel.textColor = .tertiaryLabel
            accessibilityLabel = "Note. Tap to add a note"
        }
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .button

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 5

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 6
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
}
