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

    /// Save-as-preset sheet for a frame, anchored to its tile on iPad.
    ///
    /// Only offered when Camera was opened from a Show: that's where the tile goes.
    func presentFramePresetActions(frameId: UUID, anchor: UIView?) {
        guard let showId = captureDestinationShowId,
              let show = LocalAlbumStore.shared.album(id: showId) else { return }
        Haptics.impactMedium()
        let token = ShowCameraPresetToken.token(for: frameId)
        let isSaved = show.surfaceIds?.contains(token) == true
        let sheet = UIAlertController(
            title: "Camera Frame",
            message: isSaved
                ? "This frame is already a Camera Preset in “\(show.name)”."
                : "A Camera Preset is a tile in “\(show.name)” that puts the camera "
                    + "live with this frame in one tap.",
            preferredStyle: .actionSheet
        )
        if !isSaved {
            sheet.addAction(UIAlertAction(
                title: "Save as Camera Preset", style: .default
            ) { [weak self] _ in
                guard LocalAlbumStore.shared.addCameraPreset(
                    frameId: frameId, albumId: showId
                ) else { return }
                Haptics.success()
                self?.showPresentationToast("Camera Preset added to the Show")
            })
        }
        sheet.addAction(UIAlertAction(title: isSaved ? "OK" : "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController, let anchor {
            pop.sourceView = anchor
            pop.sourceRect = anchor.bounds
        }
        present(sheet, animated: true)
    }
}
