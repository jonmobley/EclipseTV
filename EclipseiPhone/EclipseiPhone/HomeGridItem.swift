//
//  HomeGridItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Phone-only home-grid item. Specials are never part of the Apple TV Multipeer manifest.
///
/// Home has two bands: fixed tools (Logo / Camera / Website), then a Recent Shows
/// ribbon. Opening a Show keeps the tools band and replaces Recent with that Show's
/// media grid. Black is a header control. Saved bookmarks and PDFs live under +.
enum HomeGridItem: Equatable {
    case logo
    case camera
    case website
    case show(LocalAlbum)
    /// Trailing ribbon tile — creates a Show (also the empty-ribbon placeholder).
    case createShow

    /// Fixed tools row (section 0).
    static var tools: [HomeGridItem] { [.logo, .camera, .website] }

    /// Leading pinned tool count.
    static var specialCount: Int { tools.count }

    /// Recent Shows ribbon (section 1), always ending with `createShow`.
    static func recentShows(
        from albums: [LocalAlbum],
        limit: Int = 12
    ) -> [HomeGridItem] {
        var items = Array(albums.prefix(limit)).map { HomeGridItem.show($0) }
        items.append(.createShow)
        return items
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
