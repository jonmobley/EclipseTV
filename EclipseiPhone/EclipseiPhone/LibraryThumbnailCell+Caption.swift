//
//  LibraryThumbnailCell+Caption.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Caption Scrim

extension LibraryThumbnailCell {

    /// Bottom fade under any title drawn on the thumbnail.
    func updateCaptionScrim() {
        let showScrim = !captionLabel.isHidden
        captionScrimView.isHidden = !showScrim
        captionLabel.textColor = .white
        guard showScrim else { return }
        // Thumbnail → fade → title → chrome (LIVE / ⋯ stay readable on top).
        cardView.bringSubviewToFront(captionScrimView)
        cardView.bringSubviewToFront(captionLabel)
        cardView.bringSubviewToFront(liveBadge)
        if !moreButton.isHidden {
            cardView.bringSubviewToFront(moreButton)
        }
        if !rewindButton.isHidden {
            cardView.bringSubviewToFront(rewindButton)
        }
    }
}
