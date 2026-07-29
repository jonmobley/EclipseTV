//
//  LibraryThumbnailCell+Camera.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - Home Camera Tile Preview

extension LibraryThumbnailCell {

    /// Idle / app-open: warm live preview (last-frame until frames arrive).
    /// While AirPlay owns the camera: icon + LIVE badge only (no second feed).
    /// - Parameter warmPreview: When false, shows a still only (fullscreen Camera open).
    func configureCamera(isLive: Bool, lastFrame: UIImage?, warmPreview: Bool = true) {
        // Don't call resetChrome() — it would detach before we can freeze the frame.
        imageView.contentMode = .scaleAspectFill
        hideMediaBadges()
        applyCaptionPlacementForDisplayMode()

        cardView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        captionLabel.text = "Camera"
        captionLabel.isHidden = false
        updateCaptionScrim()
        setLive(isLive)
        if !isLive {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor =
                UIColor.white.withAlphaComponent(0.3).cgColor
        }

        placeholderIcon.image = UIImage(systemName: "camera.fill")
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.85)

        let airPlayOwnsCamera = ExternalDisplayManager.shared.isCameraModeActive
        if airPlayOwnsCamera {
            cancelFreezeReveal()
            detachLiveCameraPreview(saveFrame: false)
            imageView.image = nil
            imageView.alpha = 0
            placeholderIcon.isHidden = false
        } else if !warmPreview {
            // Fullscreen Camera owns the live layer — keep a still so the tile
            // doesn't flash black under the presentation animation.
            cancelFreezeReveal()
            detachLiveCameraPreview(saveFrame: false)
            imageView.image = lastFrame
            imageView.alpha = lastFrame == nil ? 0 : 1
            placeholderIcon.isHidden = lastFrame != nil
        } else {
            imageView.image = lastFrame
            imageView.alpha = lastFrame == nil ? 0 : 1
            placeholderIcon.isHidden = lastFrame != nil || CameraManager.shared.isSessionRunning
            // Attach before/while the session starts so the first frames paint immediately.
            attachLiveCameraPreview()
            if CameraManager.shared.isSessionRunning {
                scheduleFreezeReveal(delay: 0.08)
            }
        }

        accessibilityLabel = isLive ? "Camera, live" : "Camera"
        isAccessibilityElement = true
    }

    /// Detaches any live tile preview without capturing (reuse / non-camera cells).
    func recycleCameraPreview() {
        cancelFreezeReveal()
        detachLiveCameraPreview(saveFrame: false)
    }

    /// Detaches the live layer but keeps the last still visible (no black flash).
    func parkCameraPreviewShowingLastFrame() {
        cancelFreezeReveal()
        detachLiveCameraPreview(saveFrame: false)
        let still = CameraManager.shared.lastFrame
        imageView.image = still
        imageView.alpha = still == nil ? 0 : 1
        placeholderIcon.isHidden = still != nil
        placeholderIcon.image = UIImage(systemName: "camera.fill")
    }

    /// Re-applies session + Display Mode orientation on an already-configured tile.
    func refreshLiveCameraPreview() {
        guard cameraPreview?.superview != nil else { return }
        attachLiveCameraPreview()
        if CameraManager.shared.isSessionRunning {
            scheduleFreezeReveal(delay: 0.08)
        }
    }

    // MARK: - Private

    private func attachLiveCameraPreview() {
        let preview: CameraPreviewView
        if let existing = cameraPreview {
            preview = existing
        } else {
            let created = CameraPreviewView()
            created.translatesAutoresizingMaskIntoConstraints = false
            cameraPreview = created
            preview = created
        }

        if preview.superview !== cardView {
            cardView.insertSubview(preview, at: 0)
            NSLayoutConstraint.activate([
                preview.topAnchor.constraint(equalTo: cardView.topAnchor),
                preview.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
                preview.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
            ])
        }

        preview.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: .resizeAspectFill
        )
        preview.syncDisplayModeOrientation()
        cardView.bringSubviewToFront(imageView)
        cardView.bringSubviewToFront(captionScrimView)
        cardView.bringSubviewToFront(placeholderIcon)
        cardView.bringSubviewToFront(liveBadge)
        contentView.bringSubviewToFront(captionLabel)
    }

    private func detachLiveCameraPreview(saveFrame: Bool) {
        guard let preview = cameraPreview else { return }
        if saveFrame {
            CameraManager.shared.captureLastFrame(from: preview)
        }
        preview.detach()
        preview.removeFromSuperview()
    }

    /// Fades out the last-frame still so the live preview shows through.
    /// - Parameter delay: Wait before revealing (short once the session is running).
    private func scheduleFreezeReveal(delay: TimeInterval = 0.08) {
        cancelFreezeReveal()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard CameraManager.shared.isSessionRunning else { return }
            UIView.animate(withDuration: 0.15) {
                self.imageView.alpha = 0
            } completion: { _ in
                self.imageView.image = nil
                self.placeholderIcon.isHidden = true
            }
        }
        cameraFreezeRevealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelFreezeReveal() {
        cameraFreezeRevealWorkItem?.cancel()
        cameraFreezeRevealWorkItem = nil
    }
}
