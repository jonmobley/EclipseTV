//
//  LibraryThumbnailCell+PTZCamera.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CamTailKit
import SwiftUI
import UIKit

// MARK: - PTZ Camera Tile

extension LibraryThumbnailCell {

    private static let ptzPreviewTag = 0x50545A

    /// Show tile for the network PTZ camera: its live picture, caption and type icon.
    func configurePTZCamera(isLive: Bool, isLocked: Bool = false) {
        imageView.image = nil
        imageView.isHidden = true
        hideMediaBadges()
        cardView.backgroundColor = .mediaPlaceholder
        captionLabel.text = "PTZ Camera"
        captionLabel.isHidden = false
        setTypeIcon(.ptzCamera)
        placeholderIcon.isHidden = true
        updateCaptionScrim()
        setLive(isLive, isLocked: isLocked)
        setIdleBorder(width: 1, color: UIColor.white.withAlphaComponent(0.3))

        if cardView.viewWithTag(Self.ptzPreviewTag) == nil {
            // CamTailKit's preview says why there's no picture ("Camera not connected",
            // "Looking for the camera…") instead of a silent black tile.
            let live = CamTailPreviewHost.makeView(compact: true)
            live.tag = Self.ptzPreviewTag
            live.translatesAutoresizingMaskIntoConstraints = false
            cardView.insertSubview(live, aboveSubview: imageView)
            NSLayoutConstraint.activate([
                live.topAnchor.constraint(equalTo: cardView.topAnchor),
                live.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
                live.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                live.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
            ])
        }
        accessibilityLabel = isLive ? "PTZ Camera, live" : "PTZ Camera"
        isAccessibilityElement = true
    }

    /// Detaches the live picture (cell reuse / other content).
    func removePTZPreview() {
        CamTailPreviewHost.remove(cardView.viewWithTag(Self.ptzPreviewTag))
        imageView.isHidden = false
    }
}
