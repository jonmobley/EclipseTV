//
//  LibraryGridViewController+Offline.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Offline Add / Browse Helpers

extension LibraryGridViewController {

    /// Confirms deletion. Pending (not-yet-synced) items can be removed locally even
    /// while offline; TV-backed items still require a live connection to delete.
    func confirmDelete(id: String, name: String) {
        let isPending = PendingUploadStore.shared.contains(id: id)
        let message = isPending
            ? "This removes the item you added."
            : "This removes the item from your Apple TV library."
        let alert = UIAlertController(title: "Delete?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete(id: id)
        })
        present(alert, animated: true)
    }

    /// Deletes an item. Queued items are removed locally and dropped from the upload
    /// queue; a delete is still sent to the TV in case it already has the item.
    func performDelete(id: String) {
        let wasPending = PendingUploadStore.shared.contains(id: id)
        let sent = connectionManager.sendDeleteRequest(id: id)
        if wasPending {
            store.removeLocalItem(id: id)
        }
        if sent || wasPending {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            presentNotConnectedAlert()
        }
    }

    /// Shows a locally-stored item fullscreen on the phone when no Apple TV is connected,
    /// mirroring it to any connected AirPlay display. Falls back to an informational alert
    /// when the phone has no local copy (e.g. a thumbnail-only mirror of a TV item).
    func presentOfflinePreview(for item: LibraryItemDTO) {
        guard let url = LocalMediaStore.shared.localURL(forId: item.id) else {
            let alert = UIAlertController(
                title: "Not Connected",
                message: "Connect to your Apple TV to show this item on the big screen.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ExternalDisplayManager.shared.present(
            .forLibraryItem(item, thumbnail: store.thumbnail(for: item.id))
        )
        let preview = LocalMediaPreviewViewController(fileURL: url, isVideo: item.isVideo)
        present(preview, animated: true)
    }

    func presentNotConnectedAlert() {
        let alert = UIAlertController(
            title: "Not Connected",
            message: "Reconnect to your Apple TV and try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
