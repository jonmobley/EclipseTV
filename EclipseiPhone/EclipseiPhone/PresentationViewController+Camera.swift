//
//  PresentationViewController+Camera.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - Camera Presentation

extension PresentationViewController {

    /// Shows the live camera preview on the external display (primary underlay).
    func showCamera() {
        hideWeb()
        hidePDF()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()

        cameraContainer.isHidden = false
        cameraPreviewView.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: CameraPreviewView.programVideoGravity
        )
        cameraPreviewView.syncDisplayModeOrientation()
        refreshCameraFrameOverlay()
        applyCameraLayout()
    }

    /// Hides and detaches the camera preview.
    func hideCamera() {
        cameraPreviewView.detach()
        cameraContainer.isHidden = true
        cameraPreviewView.transform = .identity
        cameraPreviewView.bounds = .zero
        cameraFrameOverlayView.image = nil
        cameraFrameOverlayView.isHidden = true
        cameraFrameOverlayView.transform = .identity
        cameraFrameOverlayView.bounds = .zero
    }

    /// Fills the AirPlay surface with the mode-aspect camera panel (rotates when Vertical).
    func applyCameraLayout() {
        guard !cameraContainer.isHidden else { return }
        applyRotatedLayout(to: cameraPreviewView, in: cameraContainer, scale: 1)
        cameraPreviewView.syncDisplayModeOrientation()
        applyRotatedLayout(to: cameraFrameOverlayView, in: cameraContainer, scale: 1)
        cameraContainer.bringSubviewToFront(cameraFrameOverlayView)
    }

    /// Syncs the AirPlay PNG frame overlay from `CameraFrameStore`.
    func refreshCameraFrameOverlay() {
        let image = CameraFrameStore.shared.selectedImage
        cameraFrameOverlayView.image = image
        cameraFrameOverlayView.isHidden = image == nil || cameraContainer.isHidden
        if !cameraContainer.isHidden {
            applyCameraLayout()
        }
    }
}
