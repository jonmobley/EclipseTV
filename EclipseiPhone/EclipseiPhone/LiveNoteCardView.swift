//
//  LiveNoteCardView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Presenter note for the live item, docked under the live preview chrome.
///
/// The host pins an explicit height so the card can reserve its strip of chrome
/// before layout runs, and asks `height(forWidth:)` for the value.
final class LiveNoteCardView: UIControl {

    /// Lines shown before the note truncates.
    static let maximumLineCount = 3
    private static let horizontalInset: CGFloat = 14
    private static let verticalInset: CGFloat = 12

    private let bodyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    /// Fills the card with `note`.
    func configure(note: String) {
        bodyLabel.text = note
        accessibilityLabel = "Note. \(note)"
    }

    /// Height needed to show the current note at `width`.
    ///
    /// Measured off the label rather than `systemLayoutSizeFitting`: an unlaid
    /// card has no `preferredMaxLayoutWidth`, so the label's intrinsic size
    /// reports one long line and the card comes back a single row tall.
    func height(forWidth width: CGFloat) -> CGFloat {
        let textWidth = width - Self.horizontalInset * 2
        guard textWidth > 0 else { return 0 }
        let text = bodyLabel.sizeThatFits(
            CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        )
        return (text.height + Self.verticalInset * 2).rounded(.up)
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.applyContinuousCorner(radius: CornerRadii.card)
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .button

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = Self.maximumLineCount
        bodyLabel.isUserInteractionEnabled = false
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyLabel)

        // The host pins a rounded-up height, so the bottom inset yields rather
        // than fighting a card that is a point taller than its text.
        let bottom = bodyLabel.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: -Self.verticalInset
        )
        bottom.priority = .required - 1

        NSLayoutConstraint.activate([
            bodyLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Self.horizontalInset
            ),
            bodyLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Self.horizontalInset
            ),
            bodyLabel.topAnchor.constraint(
                equalTo: topAnchor, constant: Self.verticalInset
            ),
            bottom
        ])
    }
}
