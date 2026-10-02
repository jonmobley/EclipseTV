//
//  LiveHeaderView+PTZPreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CamTailKit
import UIKit

// MARK: - In-App PTZ Camera Preview

extension LiveHeaderView {

    private static let ptzPreviewTag = 0x50545B

    /// Shows the network PTZ camera's live picture in the hero (same stream as AirPlay).
    func showPTZPreview() {
        titleLabel.isHidden = true
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        clearCameraPreview()
        if viewWithTag(Self.ptzPreviewTag) == nil {
            let live = CamTailLiveVideoView()
            live.tag = Self.ptzPreviewTag
            live.fillsView = true
            live.isUserInteractionEnabled = false
            live.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(live, at: 0)
            NSLayoutConstraint.activate([
                live.topAnchor.constraint(equalTo: topAnchor),
                live.bottomAnchor.constraint(equalTo: bottomAnchor),
                live.leadingAnchor.constraint(equalTo: leadingAnchor),
                live.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
        setStaticPreviewHidden(true)
    }

    /// Removes the PTZ picture from the hero.
    func clearPTZPreview() {
        guard let live = viewWithTag(Self.ptzPreviewTag) else { return }
        live.removeFromSuperview()
        setStaticPreviewHidden(false)
    }
}
