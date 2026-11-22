//
//  CameraLiveViewController+OperatorMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - Camera Mode

/// Camera Mode is this same full-screen Camera with three changes: Back becomes
/// Hold to Exit (which goes Home), Show-only controls (Save as Preset, the
/// Show thumbnail grid and the TV's go-LIVE hint) are hidden, and a status pill / connect card track the
/// Mac link. Frames, quick-change stills, zoom, flip, photo and record all stay.
extension CameraLiveViewController {

    /// True when opened as Camera Mode.
    var isOperatorMode: Bool { operatorChrome != nil }

    /// Adds the Camera Mode chrome (called from `viewDidLoad` when requested).
    func setupOperatorModeIfRequested() {
        guard opensInOperatorMode, operatorChrome == nil else { return }
        let chrome = CameraOperatorChromeView(frame: view.bounds)
        chrome.onExit = { [weak self] in self?.exitOperatorMode() }
        chrome.onScan = { [weak self] in self?.presentMacScanner() }
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
        chrome.layout(panel: panelView.convert(panelView.bounds, to: view), exitFrame: backButton.frame)
        view.bringSubviewToFront(chrome)
    }

    /// Hides controls that only make sense inside a Show.
    func applyOperatorModeVisibility() {
        guard isOperatorMode else { return }
        backButton.isHidden = true
        savePresetButton.isHidden = true
        thumbGridView.isHidden = true
        // "Tap screen to go LIVE" is about the TV; the Mac link has its own card.
        tapToGoLiveHintView.isHidden = true
    }

    // MARK: - Private Helpers

    @objc private func operatorModeDidChange() {
        operatorChrome?.apply(status: CameraOperatorMode.shared.macStatus)
        layoutOperatorChromeIfNeeded()
    }

    /// Leaves Camera Mode for Home, saving any clip in progress first.
    private func exitOperatorMode() {
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

    /// Scans the Mac's Phone Camera QR code, then resumes the camera.
    private func presentMacScanner() {
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
