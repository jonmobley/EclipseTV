//
//  PresentationViewController+Media.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - Library Media (Image / Video)

extension PresentationViewController {

    /// Shows image/video host and applies Landscape / Vertical panel layout.
    func showMediaContainer() {
        mediaContainer.isHidden = false
        applyMediaLayout()
    }

    /// Hides library media and clears transforms.
    func hideMediaContainer() {
        mediaContainer.isHidden = true
        mediaContentView.transform = .identity
        mediaContentView.bounds = .zero
    }

    /// Sizes/rotates library media like camera: Vertical lays out tall then rotates
    /// into the 16:9 AirPlay framebuffer.
    func applyMediaLayout() {
        guard !mediaContainer.isHidden else { return }
        applyRotatedLayout(to: mediaContentView, in: mediaContainer, scale: 1)
        playerLayer?.frame = mediaContentView.bounds
    }
}
