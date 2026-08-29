//
//  LibraryThumbnailCell+Caption.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Caption Scrim

extension LibraryThumbnailCell {

    /// Centered title by default; swapped to sit beside Rewind.
    func installCaptionLayoutConstraints() {
        let gap = ThumbnailTypeIconView.titleSpacing
        captionLeadingToCard = captionLabel.leadingAnchor.constraint(
            equalTo: cardView.leadingAnchor, constant: 8
        )
        captionTrailingToCard = captionLabel.trailingAnchor.constraint(
            equalTo: cardView.trailingAnchor, constant: -8
        )
        captionBottomToCard = captionLabel.bottomAnchor.constraint(
            equalTo: cardView.bottomAnchor, constant: -10
        )
        captionLeadingToRewind = captionLabel.leadingAnchor.constraint(
            equalTo: rewindButton.trailingAnchor, constant: gap
        )
        captionTrailingToDuration = captionLabel.trailingAnchor.constraint(
            equalTo: durationLabel.leadingAnchor, constant: -gap
        )
        captionCenterYToRewind = captionLabel.centerYAnchor.constraint(
            equalTo: rewindButton.centerYAnchor
        )
        captionLeadingToCard.isActive = true
        captionTrailingToCard.isActive = true
        captionBottomToCard.isActive = true
    }

    /// Pins a visible title next to Rewind and stops before the duration pill.
    /// Untitled / + tiles, and titles with the type disc up top, stay centered.
    func updateCaptionLayout() {
        let show = !captionLabel.isHidden
        let hanging = show && !rewindButton.isHidden
        let dodgeDuration = show && !durationLabel.isHidden

        captionLabel.textAlignment = hanging ? .left : .center
        if hanging {
            captionLabel.numberOfLines = 1
            captionLabel.lineBreakMode = .byTruncatingTail
        }

        captionLeadingToCard.isActive = false
        captionLeadingToRewind.isActive = false
        captionCenterYToRewind.isActive = false
        captionBottomToCard.isActive = false
        captionTrailingToDuration.isActive = false
        captionTrailingToCard.isActive = false

        captionLeadingToRewind.isActive = hanging
        captionLeadingToCard.isActive = !hanging
        captionCenterYToRewind.isActive = hanging
        captionBottomToCard.isActive = !hanging
        captionTrailingToDuration.isActive = dodgeDuration
        captionTrailingToCard.isActive = !dodgeDuration
    }

    /// Bottom fade under any title drawn on the thumbnail.
    func updateCaptionScrim() {
        let showScrim = !captionLabel.isHidden
        captionScrimView.isHidden = !showScrim
        captionLabel.textColor = .white
        updateCaptionLayout()
        guard showScrim else { return }
        // Thumbnail → fade → title → chrome (⋯ stays readable on top).
        cardView.bringSubviewToFront(captionScrimView)
        cardView.bringSubviewToFront(captionLabel)
        if !typeIconOverlay.isHidden {
            cardView.bringSubviewToFront(typeIconOverlay)
        }
        raiseDurationOverlay()
        if !moreButton.isHidden {
            cardView.bringSubviewToFront(moreButton)
        }
        if !rewindButton.isHidden {
            cardView.bringSubviewToFront(rewindButton)
        }
    }
}
