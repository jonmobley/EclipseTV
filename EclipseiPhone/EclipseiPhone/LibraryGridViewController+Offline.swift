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
        } else if sent {
            // TV will confirm via manifest; drop album membership immediately.
            LocalAlbumStore.shared.removeItemFromAllAlbums(itemId: id)
            SlideshowStore.shared.removeItemFromAllSlideshows(itemId: id)
        }
        if sent || wasPending {
            MediaFitSettings.clear(forId: id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            presentNotConnectedAlert()
        }
    }

    /// Selects an item as live without the Eclipse TV app.
    ///
    /// Updates local selection always; pushes to AirPlay when connected (and remembers
    /// the source for when a display appears). Phone fullscreen preview is long-press
    /// → Preview only — never opened from a tap.
    func presentOfflineLive(for item: LibraryItemDTO) {
        if item.isVideo {
            AudioPlayerController.shared.stop()
        }
        let thumbnail = store.thumbnail(for: item.id)
        let source = PresentationSource.forLibraryItem(item, thumbnail: thumbnail)
        store.updateCurrentId(item.id)
        ExternalDisplayManager.shared.present(source)
        warnIfNoExternalDisplay()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Fullscreen swipeable gallery of local full-res copies (long-press → Preview).
    func presentLocalPreview(for item: LibraryItemDTO) {
        presentLocalPreview(for: item, in: displayItems)
    }

    /// Presents a swipeable preview gallery over `neighbors`, starting at `item`.
    func presentLocalPreview(for item: LibraryItemDTO, in neighbors: [LibraryItemDTO]) {
        let previewable = LocalMediaPreviewViewController.previewableItems(from: neighbors)
        guard let index = previewable.firstIndex(where: { $0.id == item.id }) else {
            let alert = UIAlertController(
                title: "Can't Preview",
                message: "No local copy on this phone. Add the item from Photos first.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = LocalMediaPreviewViewController(items: previewable, startIndex: index)
        present(preview, animated: true)
    }

    func presentNotConnectedAlert() {
        let alert = UIAlertController(
            title: "Not Connected",
            message: "Connect EclipseTV in Settings to complete this action. AirPlay alone is not enough for this.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
