//
//  LibraryGridViewController+ShowPDFCard.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - PDF Show Card

extension LibraryGridViewController {

    /// Preview / Rename / Cover / Arrange / Remove, plus the only place a saved PDF
    /// can be deleted.
    func pdfContextMenu(_ doc: SavedPDF, in album: LocalAlbum) -> UIMenu {
        let preview = UIAction(
            title: "Preview",
            image: UIImage(systemName: "eye")
        ) { [weak self] _ in
            self?.presentPDF(doc)
        }
        let rename = UIAction(
            title: "Rename",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.presentRenamePDFPrompt(doc)
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
        return UIMenu(children: [preview, rename] + rest.children)
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

// MARK: - Rename

extension UIViewController {

    /// Alert to rename a saved PDF. The title shows on its tile, the live header, and
    /// the reader's navigation bar, and syncs to other devices as metadata only.
    func presentRenamePDFPrompt(_ doc: SavedPDF) {
        let alert = UIAlertController(
            title: "Rename PDF", message: nil, preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = doc.title
            $0.placeholder = "Title"
            $0.autocapitalizationType = .words
            $0.clearButtonMode = .whileEditing
            $0.returnKeyType = .done
            UserDisplayName.configureTextField($0)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let save = UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text ?? ""
            do {
                try PDFStore.shared.rename(id: doc.id, to: name)
            } catch {
                self?.presentRenamePDFFailure(error)
            }
        }
        alert.addAction(save)
        present(alert, animated: true)
    }

    private func presentRenamePDFFailure(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn't Rename",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
