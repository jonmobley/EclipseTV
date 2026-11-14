//
//  CameraLiveViewController+CameraPreset.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Save Frame as Camera Preset

extension CameraLiveViewController {

    /// Hold a frame on the ribbon to save it as a Camera Preset tile in the Show.
    func installFramePresetLongPress() {
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(frameRibbonLongPressed(_:))
        )
        frameRibbonView.addGestureRecognizer(longPress)
    }

    @objc func frameRibbonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: frameRibbonView)
        guard let indexPath = frameRibbonView.indexPathForItem(at: point) else { return }
        let frames = CameraFrameStore.shared.enabledFrames
        guard frames.indices.contains(indexPath.item) else { return }
        presentFramePresetActions(
            frameId: frames[indexPath.item].id,
            anchor: frameRibbonView.cellForItem(at: indexPath)
        )
    }

    /// Actions for a held frame: Rename, plus Save as Camera Preset when Camera
    /// was opened from a Show (that's where the tile goes). Anchored on iPad.
    func presentFramePresetActions(frameId: UUID, anchor: UIView?) {
        Haptics.impactMedium()
        let show = captureDestinationShowId.flatMap { LocalAlbumStore.shared.album(id: $0) }
        let isSaved = show?.surfaceIds?.contains(
            ShowCameraPresetToken.token(for: frameId)
        ) == true
        var message: String?
        if let show {
            message = isSaved
                ? "This frame is a Camera Preset in “\(show.name)”."
                : "A Camera Preset is a tile in “\(show.name)” that puts the camera "
                    + "live with this frame in one tap."
        }
        let sheet = UIAlertController(
            title: CameraFrameStore.shared.displayName(for: frameId),
            message: message,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.presentRenameCameraFrame(frameId)
        })
        if let show, !isSaved {
            sheet.addAction(UIAlertAction(
                title: "Save as Camera Preset", style: .default
            ) { [weak self] _ in
                guard LocalAlbumStore.shared.addCameraPreset(
                    frameId: frameId, albumId: show.id
                ) else { return }
                Haptics.success()
                self?.showPresentationToast("Camera Preset added to the Show")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController, let anchor {
            pop.sourceView = anchor
            pop.sourceRect = anchor.bounds
        }
        present(sheet, animated: true)
    }
}

// MARK: - Rename Frame

extension UIViewController {

    /// Name prompt for a camera frame; a blank name goes back to "Frame N".
    func presentRenameCameraFrame(_ frameId: UUID) {
        let store = CameraFrameStore.shared
        guard let frame = store.frame(id: frameId) else { return }
        let alert = UIAlertController(
            title: "Rename Frame",
            message: "Shown on its Camera Preset tiles.",
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = frame.name
            $0.placeholder = store.displayName(for: frameId)
            $0.autocapitalizationType = .words
            $0.clearButtonMode = .whileEditing
            $0.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            CameraFrameStore.shared.rename(frameId, to: alert?.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}
