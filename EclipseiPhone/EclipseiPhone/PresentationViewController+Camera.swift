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

    /// Shows the live camera preview on the external display.
    func showCamera() {
        hideWeb()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()

        cameraContainer.isHidden = false
        // Letterbox into the Display Mode panel (9:16 Vertical / 16:9 Landscape),
        // matching the phone camera stage.
        cameraPreviewView.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: .resizeAspect
        )
        applyCameraLayout()
    }

    /// Hides and detaches the camera preview.
    func hideCamera() {
        cameraPreviewView.detach()
        cameraContainer.isHidden = true
        cameraPreviewView.transform = .identity
        cameraPreviewView.bounds = .zero
    }

    /// Fills the AirPlay surface with the mode-aspect camera panel (rotates when Vertical).
    func applyCameraLayout() {
        guard !cameraContainer.isHidden else { return }
        applyRotatedLayout(to: cameraPreviewView, in: cameraContainer, scale: 1)
    }
}
