//
//  LibraryGridViewController+RemoveUndo.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Removes members / hides tools from a Show, then offers Undo.
    ///
    /// Removing only takes items out of this Show (media stays in the library),
    /// so a snapshot of the Show's membership is enough to put everything back
    /// in the same order. Countdowns and polls are deleted outright and go
    /// through their own confirmations instead.
    func removeFromShowWithUndo(_ ids: [String], showId: UUID) {
        let store = LocalAlbumStore.shared
        guard !ids.isEmpty,
              let snapshot = store.albums.first(where: { $0.id == showId }) else { return }
        for id in ids {
            if ShowToolToken.isTool(id) {
                store.hideTool(id, albumId: showId)
            } else {
                store.remove(itemId: id, fromAlbumId: showId)
            }
        }
        Haptics.success()
        let message = ids.count == 1 ? "Removed from Show" : "Removed \(ids.count) items"
        showUndoToast(message) {
            LocalAlbumStore.shared.restoreMembership(from: snapshot)
        }
    }
}
