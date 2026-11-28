//
//  LibraryThumbnailCell+NameBelow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Name Under the Picture

/// Show grid and Library cards keep their picture clean and put the card's
/// name on one small line underneath (owner's choice "C", 2026-11-28, same as
/// Eclipse for Mac). The cell is `nameLineHeight` taller than its picture
/// there; the + tile keeps its own label inside the card.
extension LibraryThumbnailCell {

    /// Extra cell height below the picture for the name line.
    static let nameLineHeight: CGFloat = 24

    /// Gap between the picture and the name.
    private static let nameTopGap: CGFloat = 5

    /// Lines the first letter up with the picture's rounded corner.
    private static let nameInset: CGFloat = 2

    /// Adds the under-picture name label and the two card-bottom constraints.
    func installNameLabel() {
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = UIColor.label.withAlphaComponent(0.86)
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isHidden = true
        nameLabel.isAccessibilityElement = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        cardBottomToContent = cardView.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor
        )
        cardBottomAboveName = cardView.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor, constant: -Self.nameLineHeight
        )
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(
                equalTo: cardView.bottomAnchor, constant: Self.nameTopGap
            ),
            nameLabel.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor, constant: Self.nameInset
            ),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: cardView.trailingAnchor, constant: -Self.nameInset
            )
        ])
    }

    /// Switches the card between full-height and picture-plus-name layout.
    func applyNamesBelow() {
        cardBottomToContent.isActive = !namesBelow
        cardBottomAboveName.isActive = namesBelow
        if !namesBelow {
            nameLabel.isHidden = true
        }
    }

    /// Moves a visible on-card title to the line under the picture.
    ///
    /// Called from `updateCaptionScrim()`, which every titled tile runs after
    /// setting its caption; action tiles (+, New Show) skip it and keep their
    /// label inside the card.
    func moveTitleBelowIfNeeded() {
        guard namesBelow else { return }
        // Two-line captions (Prompter excerpt, Countdown end time) keep only
        // their first line, the card's name.
        let title = captionLabel.isHidden
            ? nil
            : captionLabel.text?.components(separatedBy: "\n").first
        nameLabel.text = title
        nameLabel.isHidden = (title ?? "").isEmpty
        captionLabel.isHidden = true
    }
}
