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
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()

        cameraContainer.isHidden = false
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

    /// Sizes and rotates the preview for landscape or portrait-mounted TVs.
    func applyCameraLayout() {
        guard !cameraContainer.isHidden else { return }
        applyRotatedLayout(to: cameraPreviewView, in: cameraContainer, scale: 1)
    }
}
