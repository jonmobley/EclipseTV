//
//  LiveHeaderView+LiveOverlays.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Shows live template cards and media overlays on the phone's
//               live preview, over the picture and under the hero chrome.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

// MARK: - Live Overlays

extension LiveHeaderView {

    /// Adds the overlay layer just under the LIVE badge (above any preview).
    func installLiveOverlayHost() {
        insertSubview(liveOverlayHost, belowSubview: liveBadge)
    }

    /// Fills the hero and keeps the layer above previews that were inserted
    /// at the back later (camera, web, video, countdown).
    func layoutLiveOverlayHost() {
        if liveOverlayHost.frame != bounds {
            liveOverlayHost.frame = bounds
        }
        if let index = subviews.firstIndex(of: liveOverlayHost),
           let badge = subviews.firstIndex(of: liveBadge),
           index != badge - 1 {
            insertSubview(liveOverlayHost, belowSubview: liveBadge)
        }
    }
}
