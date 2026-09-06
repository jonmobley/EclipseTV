//
//  MediaNoteCardView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Welcome-style note card without the Getting Started icon badge.
final class MediaNoteCardView: UIView {

    private let bodyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Fills the card. Empty `note` shows the tap-to-add placeholder.
    func configure(note: String?) {
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

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 5
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            bodyLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
}
