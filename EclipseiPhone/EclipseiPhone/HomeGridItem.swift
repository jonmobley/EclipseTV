//
//  HomeGridItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Phone-only home-grid item. Specials are never part of the Apple TV Multipeer manifest.
///
/// Home is a hero carousel plus Recent Shows from both Display Modes (square
/// tiles). An open Show uses `ShowGridItem` for tools and media. Black is a
/// header control. Websites and PDFs live under + or inside a Show.
enum HomeGridItem: Equatable {
    case logo
    case screensaver
    case camera
    case show(LocalAlbum)
    /// Trailing grid tile — creates a Show (also the empty-grid placeholder).
    case createShow
    /// Adds photos or a website to the open Show (empty-Show Add tile).
    case addShowMedia

    /// Max Shows shown on the Home Recent ribbon before See All.
    static let recentHomeLimit = 6

    /// Recent Shows (typically both Display Modes, by last opened).
    /// Includes `createShow` only when there are no Shows yet.
    static func recentShows(from albums: [LocalAlbum]) -> [HomeGridItem] {
        let recent = Array(albums.prefix(recentHomeLimit))
        guard !recent.isEmpty else { return [.createShow] }
        return recent.map { HomeGridItem.show($0) }
    }
}

extension HomeGridItem: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .logo:
            hasher.combine(0)
        case .screensaver:
            hasher.combine(1)
        case .camera:
            hasher.combine(2)
        case .createShow:
            hasher.combine(3)
        case .show(let album):
            hasher.combine(4)
            hasher.combine(album.id)
        case .addShowMedia:
            hasher.combine(5)
        }
    }
}
