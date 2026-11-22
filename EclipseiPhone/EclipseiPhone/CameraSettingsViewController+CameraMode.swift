//
//  CameraSettingsViewController+CameraMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - CameraModeSettingsActions

/// What the camera settings sheet asks the camera screen to do in Camera Mode.
struct CameraModeSettingsActions {
    /// Close settings and open the Mac QR scanner.
    let connectToMac: () -> Void
    /// Close settings and leave Camera Mode for Home.
    let exit: () -> Void
}

// MARK: - Camera Mode Sections

/// The Mac link and Exit Camera Mode rows, shown only in Camera Mode.
///
/// Not linked: one "Connect to Mac…" row (opens the QR scanner — the only time
/// the phone reads QR codes). Linked: a status row (Linked / Live) and
/// "Disconnect from Mac". Main thread only.
extension CameraSettingsViewController {

    /// Rows in the Mac section for the current link state.
    var macRowCount: Int {
        CameraOperatorMode.shared.macStatus.isLinkedOrTrying ? 2 : 1
    }

    /// Fills a Mac section row.
    /// - Parameters:
    ///   - config: Cell content to fill.
    ///   - cell: The cell (for selection style).
    ///   - row: Row index in the Mac section.
    func configureMacRow(_ config: inout UIListContentConfiguration, cell: UITableViewCell, row: Int) {
        let status = CameraOperatorMode.shared.macStatus
        guard status.isLinkedOrTrying else {
            config.text = "Connect to Mac…"
            config.textProperties.color = .systemBlue
            config.image = UIImage(systemName: "qrcode.viewfinder")
            return
        }
        if row == 0 {
            config.text = "Status"
            config.secondaryText = CameraOperatorChromeText.settingsStatus(for: status)
            config.textProperties.color = .label
            config.image = UIImage(systemName: status == .live ? "dot.radiowaves.left.and.right" : "link")
            config.imageProperties.tintColor = status == .live ? .systemRed : .systemBlue
            cell.selectionStyle = .none
        } else {
            config.text = "Disconnect from Mac"
            config.textProperties.color = .systemRed
            config.image = UIImage(systemName: "xmark.circle")
            config.imageProperties.tintColor = .systemRed
        }
    }

    /// Fills the Exit Camera Mode row.
    /// - Parameter config: Cell content to fill.
    func configureExitRow(_ config: inout UIListContentConfiguration) {
        config.text = "Exit Camera Mode"
        config.textProperties.color = .systemRed
        config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
        config.imageProperties.tintColor = .systemRed
    }

    /// Handles a tap in the Mac section.
    /// - Parameter row: Row index in the Mac section.
    func didSelectMacRow(_ row: Int) {
        let status = CameraOperatorMode.shared.macStatus
        if !status.isLinkedOrTrying {
            cameraModeActions?.connectToMac()
        } else if row == 1 {
            confirm(
                title: "Disconnect from Mac?",
                message: "The Mac stops getting this camera. The camera keeps working here.",
                action: "Disconnect"
            ) {
                CameraOperatorMode.shared.disconnectMac()
            }
        }
    }

    /// Asks once so a stray tap doesn't drop the Mac's camera mid-show.
    func confirmExitCameraMode() {
        confirm(
            title: "Exit Camera Mode?",
            message: CameraOperatorMode.shared.macStatus.isLinkedOrTrying
                ? "This phone stops sending its camera to the Mac."
                : "Goes back to the Home screen.",
            action: "Exit"
        ) { [weak self] in
            self?.cameraModeActions?.exit()
        }
    }

    // MARK: - Private Helpers

    private func confirm(title: String, message: String, action: String, onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in onConfirm() })
        present(alert, animated: true)
    }
}
