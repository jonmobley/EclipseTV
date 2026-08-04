//
//  CameraLiveViewController+Settings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Settings

extension CameraLiveViewController {

    /// Adds the top-right settings gear.
    func setupSettingsButton() {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.image = UIImage(systemName: "gearshape.fill", withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        settingsButton.configuration = config
        settingsButton.accessibilityLabel = "Camera Settings"
        settingsButton.translatesAutoresizingMaskIntoConstraints = true
        settingsButton.addTarget(
            self,
            action: #selector(settingsButtonTapped),
            for: .touchUpInside
        )
        view.addSubview(settingsButton)
    }

    /// Presents camera settings with an explicit Done.
    ///
    /// In Landscape Display Mode the camera is orientation-locked to landscape, where
    /// a sheet fills the screen with no grabber and no swipe-to-dismiss — so the bar
    /// button is the only way out. Edge attachment keeps it a card instead.
    ///
    /// An in-flight movie is finished and saved first — settings must not open over a
    /// live recording (no UI left on the shutter to stop it cleanly).
    @objc func settingsButtonTapped() {
        if CameraManager.shared.isRecording {
            finalizeRecordingIfNeeded { [weak self] in
                self?.presentCameraSettings()
            }
            return
        }
        presentCameraSettings()
    }

    /// Presents the Camera settings sheet.
    private func presentCameraSettings() {
        let settings = CameraSettingsViewController()
        let nav = UINavigationController(rootViewController: settings)
        nav.modalPresentationStyle = .pageSheet
        settings.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak nav, weak self] _ in
                // Settings finishes any in-flight movie before presenting; resume
                // Always Record When Live once the sheet is gone.
                nav?.dismiss(animated: true) {
                    self?.startAlwaysLiveRecordingIfNeeded()
                }
            }
        )
        nav.presentationController?.delegate = self
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        present(nav, animated: true)
    }
}

// MARK: - Settings sheet dismiss

extension CameraLiveViewController: UIAdaptivePresentationControllerDelegate {

    /// Swipe-dismiss path — Done uses the button's completion instead.
    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        startAlwaysLiveRecordingIfNeeded()
    }
}
