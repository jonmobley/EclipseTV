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

    /// Shows an item when the Eclipse TV app isn't linked: prefer AirPlay when connected,
    /// otherwise phone fullscreen preview from the local full-res copy.
    func presentOfflinePreview(for item: LibraryItemDTO) {
        let thumbnail = store.thumbnail(for: item.id)
        let source = PresentationSource.forLibraryItem(item, thumbnail: thumbnail)
        let localURL = LocalMediaStore.shared.localURL(forId: item.id)
        let airPlayConnected = ExternalDisplayManager.shared.isConnected

        // AirPlay-first: drive the TV even without Multipeer / local full-res.
        if airPlayConnected {
            ExternalDisplayManager.shared.present(source)
            store.updateCurrentId(item.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let url = localURL {
                let preview = LocalMediaPreviewViewController(
                    fileURL: url, isVideo: item.isVideo)
                present(preview, animated: true)
            }
            return
        }

        guard let url = localURL else {
            let alert = UIAlertController(
                title: "Can't Show Item",
                message: "Connect AirPlay to show this on your TV, or add it from Photos so a copy is stored on this phone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.updateCurrentId(item.id)
        let preview = LocalMediaPreviewViewController(fileURL: url, isVideo: item.isVideo)
        present(preview, animated: true)
    }

    func presentNotConnectedAlert() {
        let alert = UIAlertController(
            title: "Eclipse TV App Not Linked",
            message: "Connect the Eclipse TV app from Settings, or use AirPlay for Camera, Web, and local media.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
