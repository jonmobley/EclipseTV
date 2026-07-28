//
//  CameraLiveViewController+Frame.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Frame Overlay

extension CameraLiveViewController {

    /// Adds the Frame control and PNG overlay on the phone camera panel.
    func setupFrameOverlay() {
        frameOverlayView.contentMode = .scaleAspectFit
        frameOverlayView.clipsToBounds = true
        frameOverlayView.isUserInteractionEnabled = false
        frameOverlayView.translatesAutoresizingMaskIntoConstraints = true
        panelView.addSubview(frameOverlayView)

        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.image = UIImage(systemName: "rectangle.dashed", withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        frameButton.configuration = config
        frameButton.accessibilityLabel = "Camera Frame"
        frameButton.translatesAutoresizingMaskIntoConstraints = false
        frameButton.addTarget(self, action: #selector(frameButtonTapped), for: .touchUpInside)
        view.addSubview(frameButton)

        NSLayoutConstraint.activate([
            frameButton.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 16
            ),
            frameButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16
            ),
            frameButton.widthAnchor.constraint(equalToConstant: 44),
            frameButton.heightAnchor.constraint(equalToConstant: 44),
            goLiveButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: frameButton.trailingAnchor, constant: 12
            ),
            goLiveButton.trailingAnchor.constraint(
                lessThanOrEqualTo: logoChip.leadingAnchor, constant: -12
            )
        ])

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

    @objc func frameButtonTapped() {
        let picker = CameraFramePickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    @objc func cameraFrameStoreChanged() {
        refreshFrameOverlay()
    }
}
