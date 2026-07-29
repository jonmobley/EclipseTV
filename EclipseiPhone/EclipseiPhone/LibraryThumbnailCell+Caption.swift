//
//  LibraryThumbnailCell+Caption.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Caption Placement

extension LibraryThumbnailCell {

    /// Extra cell height for a label under the card (Landscape tools row).
    static var landscapeCaptionReserve: CGFloat { 28 }

    /// Landscape: label under the card. Vertical: label overlaid on the card.
    func applyCaptionPlacementForDisplayMode() {
        let below = !ExternalOutputSettings.isVerticalMode
        applyCaptionPlacement(belowCard: below)
    }

    /// Pins the visual card and caption for overlay vs below-card chrome.
    /// - Parameter belowCard: When true, caption sits under a rounded card.
    func applyCaptionPlacement(belowCard: Bool) {
        guard captionBelowCard != belowCard || cardFillConstraints.isEmpty else {
            refreshCaptionStyle(belowCard: belowCard)
            return
        }
        captionBelowCard = belowCard

        NSLayoutConstraint.deactivate(cardFillConstraints)
        NSLayoutConstraint.deactivate(cardAboveCaptionConstraints)
        cardFillConstraints = []
        cardAboveCaptionConstraints = []

        if belowCard {
            cardAboveCaptionConstraints = [
                cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
                cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                captionLabel.topAnchor.constraint(
                    equalTo: cardView.bottomAnchor, constant: 6),
                captionLabel.leadingAnchor.constraint(
                    equalTo: contentView.leadingAnchor, constant: 2),
                captionLabel.trailingAnchor.constraint(
                    equalTo: contentView.trailingAnchor, constant: -2),
                captionLabel.bottomAnchor.constraint(
                    equalTo: contentView.bottomAnchor)
            ]
            NSLayoutConstraint.activate(cardAboveCaptionConstraints)
            contentView.backgroundColor = .clear
        } else {
            cardFillConstraints = [
                cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
                cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                captionLabel.leadingAnchor.constraint(
                    equalTo: contentView.leadingAnchor, constant: 8),
                captionLabel.trailingAnchor.constraint(
                    equalTo: contentView.trailingAnchor, constant: -8),
                captionLabel.bottomAnchor.constraint(
                    equalTo: contentView.bottomAnchor, constant: -10)
            ]
            NSLayoutConstraint.activate(cardFillConstraints)
        }
        refreshCaptionStyle(belowCard: belowCard)
    }

    private func refreshCaptionStyle(belowCard: Bool) {
        captionLabel.textAlignment = .center
        captionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        updateCaptionScrim()
    }

    /// Shows a bottom fade when the title sits on the thumbnail (Vertical / Shows).
    func updateCaptionScrim() {
        let showScrim = !captionBelowCard && !captionLabel.isHidden
        captionScrimView.isHidden = !showScrim
        captionLabel.textColor = captionBelowCard ? .secondaryLabel : .white
        if showScrim {
            cardView.bringSubviewToFront(captionScrimView)
        }
    }
}
