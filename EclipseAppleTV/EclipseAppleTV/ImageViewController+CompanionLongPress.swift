//
//  ImageViewController+CompanionLongPress.swift
//  EclipseAppleTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Long-press inside a phone Show

/// Press-and-hold on a tile inside a Show the iPhone sent (album home).
///
/// Before, album home switched long-press off entirely, so Audio, Loop and
/// Delete could no longer be reached with the Siri Remote once a phone had
/// pushed any Show. Tiles inside a Show are ordered by the phone, so their
/// grid position is not a library index: each tile is mapped back to its
/// library item by file name. Move is left out because the phone owns the
/// Show's order. Hosted (read-only) albums keep no long-press.
/// Thread Safety: Main thread only (UIKit).
extension ImageViewController {

    /// Adds the long-press recognizer to a library tile shown inside a phone Show.
    /// - Parameter cell: A reused thumbnail cell; any older recognizer is replaced.
    func attachCompanionLongPress(to cell: ImageThumbnailCell) {
        cell.gestureRecognizers?.forEach { gesture in
            if gesture is UILongPressGestureRecognizer { cell.removeGestureRecognizer(gesture) }
        }
        let press = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress(_:))
        )
        press.minimumPressDuration = Self.companionLongPressDuration
        cell.addGestureRecognizer(press)
    }

    /// Opens the Audio/Loop/Delete (video) or Delete (still) options for a
    /// tile inside a phone Show.
    /// - Parameter cell: The pressed tile.
    func handleCompanionLongPress(on cell: ImageThumbnailCell) {
        guard let indexPath = gridView.indexPath(for: cell),
              let index = companionLibraryIndex(atItem: indexPath.item),
              let path = dataSource.getPath(at: index) else {
            logger.debug("🔵 Long press on a tile with no library item (hosted album or root)")
            return
        }
        if MediaItem.isVideoPath(path) {
            showVideoOptionsMenu(forVideoAt: index, cellIndexPath: indexPath, allowsMove: false)
        } else {
            showDeleteMenu(forImageAt: index, allowsMove: false)
        }
    }

    /// The library index behind the tile at `item` in the current phone Show,
    /// or nil at the album list or inside a hosted album.
    /// - Parameter item: The tile's position in the grid.
    /// - Returns: An index into `dataSource`, or nil.
    func companionLibraryIndex(atItem item: Int) -> Int? {
        let ids: [String]
        switch companionBrowse {
        case .album(let albumId):
            ids = displayCompanionAlbums.first { $0.id == albumId }?.itemIds ?? []
        case .leftover:
            ids = leftoverLibraryIds
        case .root, .remote:
            return nil
        }
        guard ids.indices.contains(item) else { return nil }
        return libraryIndex(forItemId: ids[item])
    }

    /// Same hold time as the flat library grid.
    private static let companionLongPressDuration: TimeInterval = 0.5
}
