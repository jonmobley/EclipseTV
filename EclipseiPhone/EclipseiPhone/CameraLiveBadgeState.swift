//
//  CameraLiveBadgeState.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Status pill above the camera panel.
///
/// The camera feed can be the output with nobody watching it — Practice Mode
/// puts it on the phone alone. A red LIVE pill there claimed an audience the
/// Show does not have, which is the same distinction the grid hero draws with
/// `LiveOutputRouting.showsHeroLiveBadge`.
enum CameraLiveBadgeState: Equatable {
    /// Viewfinder, or a cutaway still is on program — no pill.
    case hidden
    /// A display, EclipseTV, or a remote director is showing the feed.
    case live
    /// The feed is the output, but only on this iPhone.
    case practice
}

extension CameraLiveBadgeState {

    /// - Parameters:
    ///   - isCameraLive: The live feed owns the overlay (not a parked still).
    ///   - hasProgramOutput: AirPlay / HDMI, EclipseTV, or a remote director.
    static func resolve(
        isCameraLive: Bool,
        hasProgramOutput: Bool
    ) -> CameraLiveBadgeState {
        guard isCameraLive else { return .hidden }
        return hasProgramOutput ? .live : .practice
    }
}
