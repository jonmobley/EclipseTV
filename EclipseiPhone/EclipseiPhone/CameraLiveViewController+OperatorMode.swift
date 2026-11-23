//
//  CameraLiveViewController+OperatorMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - Camera Mode

/// Camera Mode is this same full-screen Camera with three changes: Back is
/// hidden (Exit Camera Mode, which goes Home, is in the camera settings), the
/// Show-only Save as Preset and thumbnail grid are hidden, and a pill shows the
/// optional Mac link (Linked / Live). Connect to Mac and Disconnect are in the
/// settings too. Frames, quick-change stills, zoom, flip, photo, record and
/// going live on a TV all stay.
extension CameraLiveViewController {

    /// True when opened as Camera Mode.
    var isOperatorMode: Bool { operatorChrome != nil }

    /// Adds the Camera Mode chrome (called from `viewDidLoad` when requested).
    func setupOperatorModeIfRequested() {
        guard opensInOperatorMode, operatorChrome == nil else { return }
        let chrome = CameraOperatorChromeView(frame: view.bounds)
        view.addSubview(chrome)
        operatorChrome = chrome
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(operatorModeDidChange),
            name: CameraOperatorMode.didChangeNotification,
            object: nil
        )
        applyOperatorModeVisibility()
    }

    /// Lays the chrome over the panel and re-hides Show-only controls.
    func layoutOperatorChromeIfNeeded() {
        guard let chrome = operatorChrome else { return }
        applyOperatorModeVisibility()
        chrome.layout(panel: panelView.convert(panelView.bounds, to: view), topRowFrame: backButton.frame)
        view.bringSubviewToFront(chrome)
    }

    /// Hides controls that only make sense inside a Show.
    func applyOperatorModeVisibility() {
        guard isOperatorMode else { return }
        backButton.isHidden = true
        savePresetButton.isHidden = true
        thumbGridView.isHidden = true
        // "Tap screen to go LIVE" is for a TV. While a Mac is linked the Mac is
        // the audience output, so the hint would only confuse.
        if CameraOperatorMode.shared.macStatus.isLinkedOrTrying {
            tapToGoLiveHintView.isHidden = true
        }
    }

    // MARK: - Private Helpers

    @objc private func operatorModeDidChange() {
        operatorChrome?.apply(status: CameraOperatorMode.shared.macStatus)
        // Re-runs the TV hint's own rule, then Camera Mode's hiding on top.
        refreshLiveChrome()
    }

    /// Leaves Camera Mode for Home, saving any clip in progress first.
    func exitOperatorMode() {
        let leave = { [weak self] in
            CameraOperatorMode.shared.deactivate()
            iPhoneMainViewController.current?.libraryViewController.closeOpenShow()
            self?.dismiss(animated: true)
        }
        if CameraManager.shared.isRecording {
            finalizeRecordingIfNeeded { leave() }
        } else {
            leave()
        }
    }

    /// Scans the Mac's Phone Camera QR code (Connect to Mac in settings), then
    /// resumes the camera. The scanner exists only while this screen is open.
    func presentMacScanner() {
        let scanner = UIHostingController(rootView: QRScannerView { [weak self] payload in
            self?.dismiss(animated: true) {
                CameraOperatorMode.shared.connect(link: payload)
                self?.startCameraPreviewIfNeeded()
            }
        })
        scanner.modalPresentationStyle = .fullScreen
        present(scanner, animated: true)
    }
}
