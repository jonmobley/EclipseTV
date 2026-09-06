//
//  LibraryGridViewController+CameraLens.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Front / Back Lens Shortcuts

/// Lens switching from the grid, so the operator does not have to open the
/// fullscreen controller to turn the camera around: the Camera tile's ⋯ menu
/// and, while the feed owns the hero, a control on the live preview itself.
extension LibraryGridViewController {

    /// True when the local lens can be swapped from this screen at all.
    ///
    /// False on a single-lens phone, before permission is granted (the controller
    /// owns that prompt), and on a remote operator, whose preview shows the
    /// director's camera rather than its own.
    var canSwitchCameraLens: Bool {
        CameraManager.shared.canFlipCamera
            && !ShowLiveSession.shared.isRemoteOperator
            && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    // MARK: - Camera Tile ⋯ Menu

    /// Controller + lens actions for the Camera tile's ⋯ menu.
    ///
    /// Rebuilt on every open: the flip action names the lens it switches to, and
    /// whether it is available at all changes with recording and permission.
    func cameraToolActions() -> [UIMenuElement] {
        [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.currentCameraToolActions() ?? [])
            }
        ]
    }

    // MARK: - Hero Flip Control

    /// Front / back control on the live preview while the camera feed owns it.
    ///
    /// Takes the trailing-bottom slot Screen Fit uses, which is free here: framing
    /// belongs to live stills and slideshows, never to the camera.
    func syncLiveCameraFlipChrome() {
        guard showsLiveHero,
              !isLiveFromOtherShow,
              ExternalDisplayManager.shared.isCameraLive,
              canSwitchCameraLens
        else {
            liveHeader.setCameraFlipVisible(false)
            return
        }
        let camera = CameraManager.shared
        liveHeader.setCameraFlipVisible(
            true,
            isFront: camera.cameraPosition == .front,
            isEnabled: !camera.isRecording
        )
    }

    /// Hero control: swap to the other lens.
    func flipLiveCameraLens() {
        let camera = CameraManager.shared
        guard canSwitchCameraLens, !camera.isRecording else { return }
        switchCameraLens(toFront: camera.cameraPosition != .front)
    }

    // MARK: - Private

    private func currentCameraToolActions() -> [UIMenuElement] {
        var actions: [UIMenuElement] = [
            UIAction(
                title: "Open Controller",
                image: UIImage(systemName: "camera.viewfinder")
            ) { [weak self] _ in
                self?.onPresentCamera?()
            }
        ]
        if let flip = cameraFlipAction() {
            actions.append(flip)
        }
        return actions
    }

    /// Switches the shared session's lens without opening the controller.
    private func cameraFlipAction() -> UIAction? {
        guard canSwitchCameraLens else { return nil }
        let camera = CameraManager.shared
        let toFront = camera.cameraPosition != .front
        let recording = camera.isRecording
        return UIAction(
            title: toFront ? "Switch to Front Camera" : "Switch to Back Camera",
            // Flipping mid-movie would tear out the writer's video input.
            subtitle: recording ? "Stop recording first" : nil,
            image: UIImage(systemName: "arrow.triangle.2.circlepath.camera"),
            attributes: recording ? [.disabled] : []
        ) { [weak self] _ in
            self?.switchCameraLens(toFront: toFront)
        }
    }

    private func switchCameraLens(toFront: Bool) {
        Haptics.impactMedium()
        CameraManager.shared.switchToCamera(
            position: toFront ? .front : .back
        ) { [weak self] in
            // The input swap rebuilds the preview connections — re-apply the tile's
            // rotation and mirroring so the new lens is not sideways or unmirrored.
            self?.syncVisibleCameraTileOrientation()
        }
    }
}
