//
//  CameraLiveViewController+Frame.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Frame Overlay + Drawer

extension CameraLiveViewController {

    /// Adds the PNG frame overlay on the phone panel.
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
        reloadFrameRibbon()
    }

    /// Opens the frame drawer; finishes an in-flight movie first if needed.
    @objc func frameButtonTapped() {
        if CameraManager.shared.isRecording {
            finalizeRecordingIfNeeded { [weak self] in
                self?.presentFrameDrawer()
            }
            return
        }
        presentFrameDrawer()
    }

    /// Page-sheet drawer for picking, importing, and deleting frames.
    private func presentFrameDrawer() {
        let picker = CameraFramePickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        present(nav, animated: true)
    }
}
