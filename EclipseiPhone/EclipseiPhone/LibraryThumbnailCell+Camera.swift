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

    /// The shared tile preview while this cell hosts it (`HomeCameraTilePreview`).
    var cameraPreview: CameraPreviewView? {
        HomeCameraTilePreview.shared.hostedView(in: cardView)
    }

    /// Idle / app-open: warm live preview (last-frame until frames arrive).
    /// While AirPlay owns the camera: centered icon + red stroke (feed is in the hero).
    /// Parked cutaway: that still fills the tile.
    /// - Parameter warmPreview: When false, shows a still only (fullscreen Camera open).
    /// - Parameter parkedStill: Quick-change still on program, shown instead of the feed.
    func configureCamera(
        isLive: Bool,
        lastFrame: UIImage?,
        parkedStill: UIImage? = nil,
        warmPreview: Bool = true,
        isLocked: Bool = false
    ) {
        // Don't call resetChrome() — it would detach before we can freeze the frame.
        imageView.contentMode = .scaleAspectFill
        hideMediaBadges()

        cardView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        captionLabel.text = "Camera"
        captionLabel.isHidden = false
        setTypeIcon(.camera)
        placeholderIcon.isHidden = true
        updateCaptionScrim()
        setLive(isLive, isLocked: isLocked)
        if !isLive {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor =
                UIColor.white.withAlphaComponent(0.3).cgColor
        }

        placeholderIcon.image = UIImage(systemName: "camera.fill")
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.85)

        applyCameraPreviewState(
            lastFrame: lastFrame,
            parkedStill: parkedStill,
            warmPreview: warmPreview
        )

        accessibilityLabel = isLive
            ? (isLocked ? "Camera, live, locked" : "Camera, live")
            : "Camera"
        isAccessibilityElement = true
    }

    /// Detaches any live tile preview without capturing (reuse / non-camera cells).
    func recycleCameraPreview() {
        guard cameraPreview != nil else { return }
        cancelFreezeReveal()
        HomeCameraTilePreview.shared.relinquish()
    }

    /// Detaches the live layer but keeps the last still visible (no black flash).
    func parkCameraPreviewShowingLastFrame() {
        cancelFreezeReveal()
        HomeCameraTilePreview.shared.unbind()
        let still = CameraManager.shared.lastFrame
        imageView.image = still
        imageView.alpha = still == nil ? 0 : 1
        placeholderIcon.isHidden = true
        placeholderIcon.image = UIImage(systemName: "camera.fill")
    }

    /// Re-applies session + phone-viewer orientation on an already-configured tile.
    func refreshLiveCameraPreview() {
        guard cameraPreview != nil else { return }
        attachLiveCameraPreview()
        guard !HomeCameraTilePreview.shared.isWarm,
              CameraManager.shared.isSessionRunning
        else {
            return
        }
        scheduleFreezeReveal()
    }

    /// Re-syncs capture rotation after the phone turns (no freeze-frame churn).
    func syncLiveCameraPreviewOrientation() {
        guard let preview = cameraPreview else { return }
        preview.syncPhoneViewerOrientation(phoneInterfaceOrientation)
    }

    // MARK: - Private

    /// Picks between a parked cutaway still, the camera icon (AirPlay owns the feed),
    /// a still (fullscreen Camera owns it) and the warm live preview.
    private func applyCameraPreviewState(
        lastFrame: UIImage?,
        parkedStill: UIImage?,
        warmPreview: Bool
    ) {
        if let parkedStill {
            cancelFreezeReveal()
            HomeCameraTilePreview.shared.unbind()
            imageView.image = parkedStill
            imageView.alpha = 1
            placeholderIcon.isHidden = true
            return
        }
        if ExternalDisplayManager.shared.isCameraModeActive {
            cancelFreezeReveal()
            HomeCameraTilePreview.shared.unbind()
            imageView.image = nil
            imageView.alpha = 0
            placeholderIcon.isHidden = false
            cardView.bringSubviewToFront(placeholderIcon)
            updateCaptionScrim()
            return
        }
        if !warmPreview {
            // Fullscreen Camera owns the live layer — keep a still so the tile
            // doesn't flash black under the presentation animation.
            cancelFreezeReveal()
            HomeCameraTilePreview.shared.unbind()
            imageView.image = lastFrame
            imageView.alpha = lastFrame == nil ? 0 : 1
            placeholderIcon.isHidden = true
            return
        }

        // Attach before/while the session starts so the first frames paint immediately.
        attachLiveCameraPreview()
        if HomeCameraTilePreview.shared.isWarm {
            // Re-hosted by a grid reload while the feed kept painting. Covering it with
            // a still would only bring back the fade — and the black underneath it.
            cancelFreezeReveal()
            imageView.image = nil
            imageView.alpha = 0
            placeholderIcon.isHidden = true
            return
        }
        imageView.image = lastFrame
        imageView.alpha = lastFrame == nil ? 0 : 1
        placeholderIcon.isHidden = true
        if CameraManager.shared.isSessionRunning {
            scheduleFreezeReveal()
        }
    }

    private func attachLiveCameraPreview() {
        let preview = HomeCameraTilePreview.shared.adopt(into: cardView)
        preview.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: CameraPreviewView.programVideoGravity
        )
        preview.syncPhoneViewerOrientation(phoneInterfaceOrientation)
        cardView.bringSubviewToFront(imageView)
        cardView.bringSubviewToFront(placeholderIcon)
        updateCaptionScrim()
        if !moreButton.isHidden {
            cardView.bringSubviewToFront(moreButton)
        }
    }

    /// Fades out the last-frame still once the live preview is actually painting.
    ///
    /// Gated on the preview layer rather than a delay: the reveal used to run 80ms
    /// after attaching, which on a rebound layer uncovered black instead of video.
    private func scheduleFreezeReveal() {
        cancelFreezeReveal()
        guard let preview = cameraPreview else { return }
        cameraFreezeRevealGate = TilePreviewPaintGate(preview: preview) { [weak self] in
            // Another cell may have adopted the preview while this gate was waiting.
            guard let self, self.cameraPreview != nil,
                  CameraManager.shared.isSessionRunning
            else {
                return
            }
            HomeCameraTilePreview.shared.noteLivePictureRevealed()
            UIView.animate(withDuration: 0.15) {
                self.imageView.alpha = 0
            } completion: { _ in
                self.imageView.image = nil
                self.placeholderIcon.isHidden = true
            }
        }
    }

    private func cancelFreezeReveal() {
        cameraFreezeRevealGate?.cancel()
        cameraFreezeRevealGate = nil
    }
}
