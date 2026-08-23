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
    ///
    /// Titles sit beside the disc (one line, tail ellipsis) and stop before
    /// the duration pill. Tool tiles keep the disc even without a poster.
    func refreshTypeIconVisibility() {
        let hasArt = imageView.image != nil && imageView.alpha > 0.5
        let allowEmpty = contentTypeIcon?.showsWithoutThumbnail == true
        let show = contentTypeIcon != nil
            && rewindButton.isHidden
            && (hasArt || allowEmpty)
        typeIconOverlay.apply(show ? contentTypeIcon : nil)
        if show {
            cardView.bringSubviewToFront(typeIconOverlay)
        }
        raiseDurationOverlay()
        updateCaptionLayout()
    }
}
