//
//  ShowCopyDestinations.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Other Shows that can receive a bulk copy, grouped for the Actions menu.
enum ShowCopyDestinations {

    /// Active Display Mode first, then the other mode. Empty groups omitted.
    ///
    /// Pass `excluding` to omit the open Show (Copy to Show). Media Library
    /// Add to Show passes `nil` so every Show is eligible.
    static func grouped(
        albums: [LocalAlbum],
        excluding openId: UUID? = nil,
        activeOrientation: ExternalOutputOrientation
    ) -> [[LocalAlbum]] {
        let shows = albums.filter { $0.id != openId }
        return [
            shows.filter { $0.orientation == activeOrientation },
            shows.filter { $0.orientation != activeOrientation }
        ].filter { !$0.isEmpty }
    }
}
