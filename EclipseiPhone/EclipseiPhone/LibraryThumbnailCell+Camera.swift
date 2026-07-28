//
//  LibraryThumbnailCell+Camera.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Camera Tile

extension LibraryThumbnailCell {

    /// Camera tool tile. While LIVE (TV already showing camera), only the icon +
    /// LIVE badge — no freeze-frame, since the main AirPlay preview has the feed.
    /// When idle, optional last-frame under the icon chrome.
    func configureCamera(isLive: Bool, lastFrame: UIImage?) {
        // Don't call resetChrome() — it would clear chrome we set below.
        imageView.contentMode = .scaleAspectFill
        hideMediaBadges()
        contentView.layer.borderWidth = 0

        contentView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        captionLabel.text = "Camera"
        captionLabel.isHidden = false
        setLive(isLive)

        placeholderIcon.image = UIImage(systemName: "camera.fill")
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.85)

        if isLive {
            imageView.image = nil
            imageView.alpha = 0
            placeholderIcon.isHidden = false
        } else if let lastFrame {
            imageView.image = lastFrame
            imageView.alpha = 1
            placeholderIcon.isHidden = true
        } else {
            imageView.image = nil
            imageView.alpha = 0
            placeholderIcon.isHidden = false
        }
    }
}
