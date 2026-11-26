//
//  LibraryGridViewController+RemoveUndo.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Removes members / hides tools / deletes countdown and poll cards from a
    /// Show, then offers Undo.
    ///
    /// Media only leaves this Show (it stays in the library), so a snapshot of
    /// the Show's membership is enough to put everything back in the same order.
    /// Countdown and Live Poll cards are deleted outright, but only once the
    /// Undo toast's time is up (`PendingDeletes`); until then they are just off
    /// the grid, so Undo brings them back whole.
    func removeFromShowWithUndo(_ ids: [String], showId: UUID) {
        let store = LocalAlbumStore.shared
        guard !ids.isEmpty, let snapshot = store.album(id: showId) else { return }
        var cardKeys: [PendingDeletes.Key] = []
        for id in ids {
            if let key = removeCardForUndo(id, showId: showId) {
                cardKeys.append(key)
            } else if ShowToolToken.isTool(id) {
                store.hideTool(id, albumId: showId)
            } else {
                store.remove(itemId: id, fromAlbumId: showId)
            }
        }
        Haptics.success()
        let message = ids.count == 1 ? "Removed from Show" : "Removed \(ids.count) items"
        showUndoToast(message) {
            for key in cardKeys {
                PendingDeletes.shared.cancel(key)
            }
            LocalAlbumStore.shared.restoreMembership(from: snapshot)
        }
    }

    /// Takes a countdown or Live Poll card off the Show and schedules its delete.
    /// - Returns: The pending-delete key, or nil when `id` is not such a card.
    private func removeCardForUndo(_ id: String, showId: UUID) -> PendingDeletes.Key? {
        let store = LocalAlbumStore.shared
        if let countdownId = ShowCountdownToken.countdownId(from: id) {
            endCountdownIfDeleting(countdownId)
            store.removeCountdown(countdownId, fromAlbumId: showId)
            PendingDeletes.shared.schedule(.showCard(id)) {
                CountdownStore.shared.delete(id: countdownId)
            }
            return .showCard(id)
        }
        if let livePollId = ShowLivePollToken.livePollId(from: id) {
            endQuestPollIfRemovingMembership(livePollId)
            store.removeLivePoll(livePollId, fromAlbumId: showId)
            PendingDeletes.shared.schedule(.showCard(id)) {
                LivePollStore.shared.delete(id: livePollId)
            }
            return .showCard(id)
        }
        return nil
    }
}
