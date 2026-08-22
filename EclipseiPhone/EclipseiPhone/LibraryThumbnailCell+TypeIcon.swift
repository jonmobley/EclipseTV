//
//  LibraryThumbnailCell+TypeIcon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Content Type Overlay

extension LibraryThumbnailCell {

    /// Pins the type disc to the bottom-leading corner of the card.
    func installTypeIcon() {
        typeIconOverlay.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(typeIconOverlay)
        NSLayoutConstraint.activate([
            typeIconOverlay.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor,
                constant: ThumbnailTypeIconView.inset
            ),
            typeIconOverlay.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor,
                constant: -ThumbnailTypeIconView.inset
            ),
            typeIconOverlay.widthAnchor.constraint(
                equalToConstant: ThumbnailTypeIconView.side
            ),
            typeIconOverlay.heightAnchor.constraint(
                equalToConstant: ThumbnailTypeIconView.side
            )
        ])
    }

    /// Sets the content-type glyph. Hidden when there is no thumbnail, the item
    /// is unavailable, or Rewind already occupies this corner.
    func setTypeIcon(_ icon: ThumbnailTypeIcon?) {
        contentTypeIcon = icon
        refreshTypeIconVisibility()
    }

    /// Recomputes overlay visibility after rewind / chrome changes.
    func refreshTypeIconVisibility() {
        let hasArt = imageView.image != nil && imageView.alpha > 0.5
        let show = contentTypeIcon != nil && rewindButton.isHidden && hasArt
        typeIconOverlay.apply(show ? contentTypeIcon : nil)
        let captionPad = show && !captionLabel.isHidden
        captionLeadingConstraint.constant = captionPad
            ? ThumbnailTypeIconView.captionClearance
            : 8
        guard show else { return }
        cardView.bringSubviewToFront(typeIconOverlay)
    }
}
