//
//  LibraryGridViewController+DualPath.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

extension LibraryGridViewController {

    /// Camera / web / PDF / logo / black stay on AirPlay. Parks EclipseTV when both are up.
    func announceAirPlayOverlayIfLinked() {
        guard AirPlayOverlayPark.shouldParkTV(
            eclipseTVOnline: store.isOnline,
            airPlayConnected: ExternalDisplayManager.shared.isConnected
        ) else { return }
        _ = AirPlayOverlayPark.park(using: connectionManager)
        onStatusMessage?(
            "Showing on AirPlay. EclipseTV is parked."
        )
    }

    /// Releases EclipseTV park when AirPlay left an overlay for library / screensaver.
    /// Background / Screensaver / Blackout stay parked.
    func clearTVParkIfAirPlayReturnedToLibrary() {
        let mgr = ExternalDisplayManager.shared
        guard !mgr.isOverlayLive else { return }
        if isBlackSelected || isLogoSelected || isScreensaverSelected {
            announceAirPlayOverlayIfLinked()
            return
        }
        _ = AirPlayOverlayPark.clear(using: connectionManager)
    }
}
