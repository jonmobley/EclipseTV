//
//  PresentationViewController+LiveOverlays.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Keeps the template / media overlay layer on top of the
//               external display's stage.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

// MARK: - Live Overlays

extension PresentationViewController {

    /// Adds the overlay layer above every output view.
    func installLiveOverlayHost() {
        view.addSubview(liveOverlayHost)
        layoutLiveOverlayHost()
    }

    /// Matches the overlay layer to the stage and keeps it frontmost, so
    /// containers added later (web, camera, transitions) never cover it.
    func layoutLiveOverlayHost() {
        if liveOverlayHost.frame != stageView.frame {
            liveOverlayHost.frame = stageView.frame
        }
        liveOverlayHost.bringToFront()
    }
}
