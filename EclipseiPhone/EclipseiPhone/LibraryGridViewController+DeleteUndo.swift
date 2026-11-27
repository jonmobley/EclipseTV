//
//  LibraryGridViewController+DeleteUndo.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Delete Show / Library item with Undo

extension LibraryGridViewController {

    /// Deletes a Show (after its confirmation) with an Undo toast as a second chance.
    ///
    /// The Show is only hidden while the toast is up (`PendingDeletes`); its
    /// slideshows, countdowns, polls and scripts, and its iCloud record, are
    /// deleted when the toast's time runs out. Undo shows it again, and reopens
    /// it when it was the open Show.
    /// - Parameter id: The Show to delete.
    func deleteShowWithUndo(id: UUID) {
        let store = LocalAlbumStore.shared
        guard let show = store.album(id: id) else { return }
        let wasOpen = openShowId == id
        if wasOpen {
            closeOpenShow()
        }
        guard store.beginPendingDelete(id: id) else { return }
        PendingDeletes.shared.schedule(.show(id)) {
            LocalAlbumStore.shared.commitPendingDelete(id: id)
        }
        Haptics.success()
        showUndoToast("Deleted “\(show.name)”") { [weak self] in
            guard PendingDeletes.shared.cancel(.show(id)),
                  LocalAlbumStore.shared.cancelPendingDelete(id: id) else {
                self?.showPresentationToast("Already deleted")
                return
            }
            if wasOpen {
                self?.openLocalAlbum(id: id)
            }
        }
    }

    /// Asks "Delete Show?", then deletes it with an Undo toast.
    /// - Parameter show: The Show to delete.
    func confirmDeleteShow(_ show: LocalAlbum) {
        askToDelete(
            title: "Delete Show?",
            message: "“\(show.name)” is removed from Home. Its images and videos stay on this iPhone and any linked EclipseTV.",
            actionTitle: "Delete"
        ) { [weak self] in
            self?.deleteShowWithUndo(id: show.id)
        }
    }

    /// Asks "Delete?", then deletes a Library photo or video with an Undo toast.
    ///
    /// The tile is hidden at once; the real delete (`performDelete`: Apple TV
    /// request, Show memberships, local file) runs once the toast's time is up.
    /// With no EclipseTV linked, the Apple TV's copy goes the next time it links.
    /// - Parameter id: Library item id.
    func deleteLibraryItemWithUndo(id: String) {
        let isPending = PendingUploadStore.shared.contains(id: id)
        let message = Self.libraryDeleteMessage(
            isPending: isPending, isLinked: connectionManager.canSendLibraryCommands
        )
        askToDelete(title: "Delete?", message: message) {
            [weak self] in
            self?.offerLibraryDeleteUndo(id: id) { [weak self] in
                self?.performDelete(id: id)
            }
        }
    }
}

// MARK: - Shared Library delete flow

extension UIViewController {

    /// The "Delete?" message for a Library item.
    /// - Parameters:
    ///   - isPending: Whether the item was added here and not yet synced.
    ///   - isLinked: Whether an EclipseTV is linked right now.
    static func libraryDeleteMessage(isPending: Bool, isLinked: Bool) -> String {
        if isPending { return "This removes the item you added." }
        return isLinked
            ? "This removes the item from your Apple TV library."
            : "This removes the item from Library. Your Apple TV deletes its copy the next time it's linked."
    }

    /// Shows an "Are you sure?" alert with Cancel and a red action button.
    /// - Parameters:
    ///   - title: Alert title, e.g. "Delete Show?".
    ///   - message: What will happen.
    ///   - actionTitle: The red button's title.
    ///   - onConfirm: Runs when the red button is tapped.
    func askToDelete(
        title: String,
        message: String,
        actionTitle: String = "Delete",
        onConfirm: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive) { _ in
            onConfirm()
        })
        present(alert, animated: true)
    }

    /// Hides a Library item, shows an Undo toast, and runs `commit` afterwards.
    /// - Parameters:
    ///   - id: Library id (media id, or a PDF's uuid string).
    ///   - commit: The real delete, run when the toast's time is up.
    func offerLibraryDeleteUndo(id: String, commit: @escaping () -> Void) {
        let key = PendingDeletes.Key.libraryItem(id)
        PendingDeletes.shared.schedule(key, commit: commit)
        Haptics.success()
        showUndoToast("Deleted from Library") { [weak self] in
            guard PendingDeletes.shared.cancel(key) else {
                self?.showPresentationToast("Already deleted")
                return
            }
        }
    }

    /// Asks "Delete PDF?", then deletes it with an Undo toast: hidden from
    /// Library now, removed from every Show and from disk once the toast's time is up.
    /// - Parameter doc: The PDF to delete.
    func deletePDFWithUndo(_ doc: SavedPDF) {
        askToDelete(
            title: "Delete PDF?",
            message: "“\(doc.title)” is removed from every Show and from Library."
        ) { [weak self] in
            self?.commitPDFDeleteWithUndo(doc)
        }
    }

    private func commitPDFDeleteWithUndo(_ doc: SavedPDF) {
        offerLibraryDeleteUndo(id: doc.id.uuidString) {
            let manager = ExternalDisplayManager.shared
            if manager.isPDFLive, manager.livePDFDocumentId == doc.id {
                manager.stopPDFAndRestoreLibrary()
            }
            PDFStore.shared.remove(id: doc.id)
        }
    }
}
