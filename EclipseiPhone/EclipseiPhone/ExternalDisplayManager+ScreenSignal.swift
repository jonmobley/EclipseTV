//
//  ExternalDisplayManager+ScreenSignal.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Keeps `ExternalOutputSettings.connectedScreenSignal` in step with the
/// external screen, so an odd-shaped screen (an LED wall behind an EDID box)
/// is filled at its real size.
extension ExternalDisplayManager {

    /// Re-reads the connected external screen. Call after the operator changes
    /// the Screen Size choice, so a size the screen offers is switched to.
    func refreshScreenSignal() {
        refreshScreenSignal(for: connectedExternalScreen)
    }

    /// Reads `screen` (nil after a disconnect) and tells the app when the
    /// picture's shape changed.
    ///
    /// The notification goes out on the next main-queue turn: this runs while
    /// the manager is attaching to the screen, and the notification's observers
    /// call back into the manager.
    func refreshScreenSignal(for screen: UIScreen?) {
        let signal = screen.map {
            ExternalScreenSignal.prepare($0, wanted: Self.wantedScreenSize)
        }
        guard ExternalOutputSettings.updateConnectedScreenSignal(signal) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ExternalOutputSettings.didChangeNotification,
                object: nil
            )
        }
    }

    /// Handles `UIScreen.modeDidChangeNotification` for the external screen.
    func screenModeDidChange(_ screen: UIScreen?) {
        guard let screen, screen === connectedExternalScreen else { return }
        refreshScreenSignal(for: screen)
    }

    // MARK: - Private Helpers

    /// The operator's active custom size, as a signal size to look for.
    private static var wantedScreenSize: ExternalScreenSignal.PixelSize? {
        ExternalOutputSettings.activeCustomSize.map {
            ExternalScreenSignal.PixelSize(width: $0.width, height: $0.height)
        }
    }

    /// The screen of the connected AirPlay / HDMI scene, if any.
    private var connectedExternalScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { Self.isExternalDisplayRole($0.session.role) }?
            .screen
    }
}
