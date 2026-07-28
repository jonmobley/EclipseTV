//
//  CameraLiveViewController+LogoChip.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Logo Chip

extension CameraLiveViewController {

    /// Adds the corner Logo chip and listens for LogoStore updates.
    func setupLogoChip() {
        logoChip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logoChip)
        NSLayoutConstraint.activate([
            logoChip.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16),
            logoChip.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            logoChip.widthAnchor.constraint(equalToConstant: 72),
            logoChip.heightAnchor.constraint(equalToConstant: 72)
        ])
        logoChip.addTarget(self, action: #selector(logoChipTapped), for: .touchUpInside)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(logoStoreChanged),
            name: LogoStore.didChangeNotification,
            object: nil
        )
    }

    /// Refreshes chip image and LIVE chrome from the current park state.
    func refreshLogoChip() {
        logoChip.reloadImage()
        logoChip.isLogoLive = ExternalDisplayManager.shared.isCameraParkedOnLogo
    }

    @objc func logoChipTapped() {
        // Logo park is only meaningful once camera is live on AirPlay.
        guard ExternalDisplayManager.shared.isCameraModeActive else { return }
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnLogo {
            mgr.resumeCameraFromLogoPark()
        } else {
            mgr.parkCameraOnLogo()
        }
        logoChip.isLogoLive = mgr.isCameraParkedOnLogo
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc func logoStoreChanged() {
        logoChip.reloadImage()
    }
}
