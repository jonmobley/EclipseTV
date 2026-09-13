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

/// What a tap on the Camera Show tile means.
enum CameraTileTapAction: Equatable {
    /// Put the feed on program. The controller stays closed — output is the point
    /// and the viewfinder is optional, unlike a website or PDF.
    case goLive
    /// Open the phone controller. Live is already handled, so this is all the tap
    /// can still mean.
    case openController
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

    /// First tap goes live; a tap on the already-live tile opens the controller.
    ///
    /// Website and PDF cards open their controller on every tap, so the tile the
    /// user closed out of is always one tap away again. Camera withholds the
    /// controller on the way live, which left the second tap doing nothing at all
    /// and the closed viewfinder reachable only from the hero or ⋯.
    static func cameraTileTap(isCameraTileLive: Bool) -> CameraTileTapAction {
        isCameraTileLive ? .openController : .goLive
    }
}
