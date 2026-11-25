//
//  LibraryGridViewController+DeleteUndo.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Delete Show / Library item with Undo

extension LibraryGridViewController {

    /// Deletes a Show with an Undo toast instead of a confirmation.
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

    /// Deletes a Library photo or video with an Undo toast instead of a confirmation.
    ///
    /// The tile is hidden at once; the real delete (`performDelete`: Apple TV
    /// request, Show memberships, local file) runs once the toast's time is up.
    /// A TV-backed item still needs the EclipseTV link, checked up front.
    /// - Parameter id: Library item id.
    func deleteLibraryItemWithUndo(id: String) {
        let isPending = PendingUploadStore.shared.contains(id: id)
        guard isPending || connectionManager.canSendLibraryCommands else {
            presentNotConnectedAlert()
            return
        }
        offerLibraryDeleteUndo(id: id) { [weak self] in
            self?.performDelete(id: id)
        }
    }
}

// MARK: - Shared Library delete flow

extension UIViewController {

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

    /// Deletes a saved PDF with an Undo toast: hidden from Library now, removed
    /// from every Show and from disk once the toast's time is up.
    /// - Parameter doc: The PDF to delete.
    func deletePDFWithUndo(_ doc: SavedPDF) {
        offerLibraryDeleteUndo(id: doc.id.uuidString) {
            let manager = ExternalDisplayManager.shared
            if manager.isPDFLive, manager.livePDFDocumentId == doc.id {
                manager.stopPDFAndRestoreLibrary()
            }
            PDFStore.shared.remove(id: doc.id)
        }
    }
}
