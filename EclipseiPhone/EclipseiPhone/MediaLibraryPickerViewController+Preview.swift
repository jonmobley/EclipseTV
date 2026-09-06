//
//  MediaLibraryPickerViewController+Preview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Preview

extension MediaLibraryPickerViewController {

    /// Fullscreen Preview on top of Media Library (dismiss returns here, not Home).
    func previewMedia(_ item: LibraryItemDTO) {
        guard let url = LocalMediaStore.shared.localURL(forId: item.id) else {
            presentCannotPreview()
            return
        }
        if item.isVideo {
            previewVideo(item, fileURL: url)
            return
        }
        previewImage(item)
    }

    /// Pushes the PDF reader so Back returns to Media Library.
    func previewPDF(_ doc: SavedPDF) {
        guard !isAlreadyOpen(PDFRemoteViewController.self) else { return }
        guard let url = PDFStore.shared.fileURL(for: doc.id) else {
            let alert = UIAlertController(
                title: "PDF Missing",
                message: "That file is no longer on this iPhone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let remote = PDFRemoteViewController(document: doc, fileURL: url)
        if let nav = navigationController {
            nav.pushViewController(remote, animated: true)
        } else {
            let wrapped = UINavigationController(rootViewController: remote)
            wrapped.modalPresentationStyle = .fullScreen
            present(wrapped, animated: true)
        }
    }

    private func previewImage(_ item: LibraryItemDTO) {
        guard !isAlreadyOpen(LocalMediaPreviewViewController.self),
              !isAlreadyOpen(LocalVideoPreviewViewController.self) else { return }
        let previewable = LocalMediaPreviewViewController.imagePreviewableItems(
            from: TVLibraryStore.shared.items
        )
        guard let index = previewable.firstIndex(where: { $0.id == item.id }) else {
            presentCannotPreview()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = LocalMediaPreviewViewController(
            items: previewable,
            startIndex: index
        )
        preview.onDismiss = { [weak self] id in
            self?.revealItemAfterPreview(id: id)
        }
        preview.optionsMenuProvider = { [weak self] context in
            self?.previewOptionsMenu(context)
        }
        present(preview, animated: true)
    }

    /// Parks the grid on the tile the gallery closed on (if the filter still shows it).
    private func revealItemAfterPreview(id: String) {
        guard let index = items.firstIndex(of: .media(id)) else { return }
        collectionView.revealItemIfNeeded(at: IndexPath(item: index, section: 0))
    }

    private func previewVideo(_ item: LibraryItemDTO, fileURL: URL) {
        guard !isAlreadyOpen(LocalVideoPreviewViewController.self),
              !isAlreadyOpen(LocalMediaPreviewViewController.self) else { return }
        AudioAmbientPolicy.applyYieldIfNeeded(
            for: PresentationSource.video(
                fileURL,
                isLooping: item.isLooping ?? false,
                isMuted: item.isMuted ?? false
            )
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = LocalVideoPreviewViewController(
            fileURL: fileURL,
            isMuted: item.isMuted ?? false,
            isLooping: item.isLooping ?? false
        )
        present(preview, animated: true)
    }

    private func presentCannotPreview() {
        let alert = UIAlertController(
            title: "Can't Preview",
            message: "No local copy on this phone. Add the item from Photos first.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
