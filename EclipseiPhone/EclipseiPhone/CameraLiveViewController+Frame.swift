//
//  CameraLiveViewController+Frame.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Frame Overlay

extension CameraLiveViewController {

    /// Adds the PNG frame overlay on the phone panel (picker lives in Settings).
    func setupFrameOverlay() {
        frameOverlayView.contentMode = .scaleAspectFit
        frameOverlayView.clipsToBounds = true
        frameOverlayView.isUserInteractionEnabled = false
        frameOverlayView.translatesAutoresizingMaskIntoConstraints = true
        panelView.addSubview(frameOverlayView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cameraFrameStoreChanged),
            name: CameraFrameStore.didChangeNotification,
            object: nil
        )
        refreshFrameOverlay()
    }

    /// Keeps the PNG overlay matched to the phone camera panel.
    func layoutFrameOverlay() {
        frameOverlayView.frame = previewView.frame
        frameOverlayView.transform = previewView.transform
        panelView.bringSubviewToFront(frameOverlayView)
    }

    /// Reloads the selected frame image onto the phone overlay.
    func refreshFrameOverlay() {
        frameOverlayView.image = CameraFrameStore.shared.selectedImage
        frameOverlayView.isHidden = frameOverlayView.image == nil
        layoutFrameOverlay()
    }

    @objc func cameraFrameStoreChanged() {
        refreshFrameOverlay()
    }
}
