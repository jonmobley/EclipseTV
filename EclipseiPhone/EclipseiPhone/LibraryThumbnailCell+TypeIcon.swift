//
//  LibraryThumbnailCell+TypeIcon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Content Type Overlay

extension LibraryThumbnailCell {

    /// Pins the type disc to the top-leading corner of the card.
    func installTypeIcon() {
        typeIconOverlay.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(typeIconOverlay)
        NSLayoutConstraint.activate([
            typeIconOverlay.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor,
                constant: ThumbnailTypeIconView.inset
            ),
            typeIconOverlay.topAnchor.constraint(
                equalTo: cardView.topAnchor,
                constant: ThumbnailTypeIconView.inset
            ),
            typeIconOverlay.widthAnchor.constraint(
                equalToConstant: ThumbnailTypeIconView.side
            ),
            typeIconOverlay.heightAnchor.constraint(
                equalToConstant: ThumbnailTypeIconView.side
            )
        ])
    }

    /// Sets the content-type glyph. Hidden for photos, missing art, or when
    /// the item is unavailable. Rewind lives in the opposite corner, so both
    /// can show.
    func setTypeIcon(_ icon: ThumbnailTypeIcon?) {
        contentTypeIcon = icon
        refreshTypeIconVisibility()
    }

    /// Recomputes overlay visibility after chrome changes.
    ///
    /// Tool tiles keep the disc even without a poster.
    func refreshTypeIconVisibility() {
        let hasArt = imageView.image != nil && imageView.alpha > 0.5
        let allowEmpty = contentTypeIcon?.showsWithoutThumbnail == true
        let show = contentTypeIcon?.showsOnThumbnail == true
            && (hasArt || allowEmpty)
        typeIconOverlay.apply(show ? contentTypeIcon : nil)
        if show {
            cardView.bringSubviewToFront(typeIconOverlay)
        }
        raiseDurationOverlay()
        updateCaptionLayout()
    }
}
