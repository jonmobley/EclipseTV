//
//  HomeGridItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Phone-only home-grid item. Specials are never part of the Apple TV Multipeer manifest.
///
/// Home is a single Recent Shows grid. Opening a Show adds the tools band
/// (Logo / Camera / Website) and replaces Recent with that Show's media grid.
/// Black is a header control. Saved bookmarks and PDFs live under +.
enum HomeGridItem: Equatable {
    case logo
    case camera
    case website
    case show(LocalAlbum)
    /// Trailing grid tile — creates a Show (also the empty-grid placeholder).
    case createShow

    /// Fixed tools row (section 0).
    static var tools: [HomeGridItem] { [.logo, .camera, .website] }

    /// Leading pinned tool count.
    static var specialCount: Int { tools.count }

    /// Every Show in the current Display Mode, always ending with `createShow`.
    static func recentShows(from albums: [LocalAlbum]) -> [HomeGridItem] {
        albums.map { HomeGridItem.show($0) } + [.createShow]
    }
}

extension HomeGridItem: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .logo:
            hasher.combine(0)
        case .camera:
            hasher.combine(1)
        case .website:
            hasher.combine(2)
        case .createShow:
            hasher.combine(3)
        case .show(let album):
            hasher.combine(4)
            hasher.combine(album.id)
        }
    }
}
