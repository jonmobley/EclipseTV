//
//  CameraStillRibbonItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Which camera-mode still is on program, if any.
enum CameraParkedStill: Equatable {
    /// Show Background (`LogoStore`).
    case background
    /// A user-picked quick-change still.
    case cutaway(UUID)
}

/// One cell in the camera stills ribbon (Background, quick-change stills, add).
enum CameraStillRibbonItem: Equatable {
    case background
    /// A user-picked quick-change still. `+` adds another of these.
    case cutaway(UUID)
    case add
}

enum CameraStillRibbon {

    /// Builds the camera stills ribbon: Background, quick-change stills, then +.
    static func items(
        cutawayIds: [UUID],
        canAdd: Bool
    ) -> [CameraStillRibbonItem] {
        var items: [CameraStillRibbonItem] = [.background]
        items.append(contentsOf: cutawayIds.map { .cutaway($0) })
        if canAdd {
            items.append(.add)
        }
        return items
    }

    /// Camera Show tile is live for the feed or a parked quick-change still.
    static func cameraTileIsLive(
        isCameraLive: Bool,
        parked: CameraParkedStill?
    ) -> Bool {
        if isCameraLive { return true }
        if case .cutaway = parked { return true }
        return false
    }

    /// Closing camera while parked on Background hands live off to that tile.
    static func shouldCommitToBackground(parked: CameraParkedStill?) -> Bool {
        parked == .background
    }
}
