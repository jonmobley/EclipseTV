//
//  LibraryGridViewController+DualPath.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

extension LibraryGridViewController {

    /// Camera / web / PDF / logo / black stay on AirPlay. EclipseTV keeps its library.
    func announceAirPlayOverlayIfLinked() {
        guard store.isOnline, ExternalDisplayManager.shared.isConnected else { return }
        onStatusMessage?(
            "Showing on AirPlay. EclipseTV is still on the library."
        )
    }
}
