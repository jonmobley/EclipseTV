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

    /// Opens Camera Mode: the full-screen Camera, optionally linked to a Mac.
    /// - Parameter link: A scanned Mac Phone Camera QR link, or nil to relink
    ///   the last Mac (none: a plain camera until Connect to Mac in settings).
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

    /// Asks before a link from outside the app (a tapped link or the Camera
    /// app's QR reader) starts sending this camera, naming the Mac it points at.
    /// - Parameter link: The `eclipse://phone-camera?...` link that opened the app.
    func confirmCameraModeLink(_ link: String) {
        guard CameraModeLinkPolicy.isAllowed(link), let host = CameraModeLinkPolicy.macHost(in: link) else {
            presentCameraModeAlert(
                title: "Can't Use This Link",
                message: "Camera Mode only connects to Eclipse on a Mac on this Wi-Fi network.",
                confirmTitle: nil
            ) {}
            return
        }
        presentCameraModeAlert(
            title: "Send Camera to Mac?",
            message: "This phone's camera will be sent to Eclipse on the Mac at \(host).",
            confirmTitle: "Send Camera"
        ) { [weak self] in
            self?.presentCameraMode(link: link)
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

    private func presentCameraModeAlert(
        title: String,
        message: String,
        confirmTitle: String?,
        onConfirm: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: confirmTitle == nil ? "OK" : "Cancel", style: .cancel))
        if let confirmTitle {
            alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in onConfirm() })
        }
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
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
