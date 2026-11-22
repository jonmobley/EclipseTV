//
//  iPhoneMainViewController+CameraMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Mode Entry

extension iPhoneMainViewController {

    /// The app's main screen, for deep links and Camera Mode exit.
    static var current: iPhoneMainViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            if let nav = window.rootViewController as? UINavigationController,
               let main = nav.viewControllers.first as? iPhoneMainViewController {
                return main
            }
        }
        return nil
    }

    /// Opens Camera Mode: the full-screen Camera, sending its picture to a Mac.
    /// - Parameter link: A scanned Mac Phone Camera QR link, or nil to reuse
    ///   the saved one (and show Scan Mac QR Code if there is none).
    func presentCameraMode(link: String? = nil) {
        CameraOperatorMode.shared.activate(link: link)
        if let open = openController(ofType: CameraLiveViewController.self) {
            // Already in a camera screen: leave it so Camera Mode opens clean.
            guard !open.isOperatorMode else { return }
            open.dismiss(animated: false) { [weak self] in
                self?.presentCameraMode(link: nil)
            }
            return
        }
        dismissPresentedForCameraMode { [weak self] in
            self?.showCameraModeScreen()
        }
    }

    /// Reopens Camera Mode after a relaunch if the volunteer never left it.
    func restoreCameraModeIfNeeded() {
        guard CameraOperatorMode.shared.isActive else { return }
        presentCameraMode()
    }

    /// Home dropdown entry for Camera Mode.
    func cameraModeAction() -> UIAction {
        UIAction(
            title: "Camera Mode",
            image: UIImage(systemName: "video.badge.waveform")
        ) { [weak self] _ in
            self?.presentCameraMode()
        }
    }

    // MARK: - Private Helpers

    /// Closes sheets (Settings, Library…) so the camera is the only screen.
    private func dismissPresentedForCameraMode(then completion: @escaping () -> Void) {
        guard presentedViewController != nil else {
            completion()
            return
        }
        dismiss(animated: false, completion: completion)
    }

    private func showCameraModeScreen() {
        libraryViewController.closeOpenShow()
        libraryViewController.parkHomeCameraTileForFullscreen()
        let cameraVC = CameraLiveViewController()
        cameraVC.opensInOperatorMode = true
        cameraVC.modalPresentationStyle = .fullScreen
        present(cameraVC, animated: true)
    }
}
