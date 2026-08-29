//
//  LibraryGridViewController+ShowPDFCard.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - PDF Show Card

extension LibraryGridViewController {

    /// Preview / Cover / Arrange / Remove, plus the only place a saved PDF can be deleted.
    func pdfContextMenu(_ doc: SavedPDF, in album: LocalAlbum) -> UIMenu {
        let preview = UIAction(
            title: "Preview",
            image: UIImage(systemName: "eye")
        ) { [weak self] _ in
            self?.presentPDF(doc)
        }
        let delete = UIAction(
            title: "Delete PDF",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeletePDF(doc)
        }
        let rest = memberContextMenu(
            itemId: doc.id.uuidString,
            in: album,
            extras: [delete]
        )
        return UIMenu(children: [preview] + rest.children)
    }

    /// Deleting drops the file, so warn that every Show loses the card.
    private func confirmDeletePDF(_ doc: SavedPDF) {
        let alert = UIAlertController(
            title: "Delete PDF?",
            message: "“\(doc.title)” is removed from every Show and from Library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            let manager = ExternalDisplayManager.shared
            if manager.isPDFLive, manager.livePDFDocumentId == doc.id {
                manager.stopPDFAndRestoreLibrary()
            }
            PDFStore.shared.remove(id: doc.id)
        })
        present(alert, animated: true)
    }
}
