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
    ///
    /// Routes by `MediaSyncPresence` first: a purged item hands off to the re-send
    /// flow, an iCloud-only item downloads (with a toast) and comes back through
    /// here, and only a genuinely stranded item hits the alert.
    func previewMedia(_ item: LibraryItemDTO) {
        let presence = MediaSyncPresence.resolve(for: item)
        if presence == .purgedOnTV {
            onRequestResend?(item.id)
            return
        }
        if presence.wantsCloudDownload {
            downloadFromCloudAndPreview(item)
            return
        }
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

    /// Fetches `item`'s asset from iCloud, then re-enters `previewMedia`.
    ///
    /// Mirrors `LibraryGridViewController.downloadFromCloud`: the tile picks up the
    /// "Downloading…" pill from the store's state change, and the toast is the
    /// picker's own acknowledgement of the tap.
    private func downloadFromCloudAndPreview(_ item: LibraryItemDTO) {
        showPresentationToast(String(localized: "Downloading from iCloud…"), duration: 8)
        EclipseSyncController.shared.backend.downloadAsset(
            id: item.id, progress: nil
        ) { [weak self] result in
            guard let self else { return }
            self.removePresentationToastIfPresent()
            switch result {
            case .success:
                var available = item
                available.isAvailable = true
                self.previewMedia(available)
            case .failure(let error):
                Haptics.error()
                let alert = UIAlertController(
                    title: "Download Failed",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
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
        Haptics.impactLight()
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
        Haptics.impactLight()
        let preview = LocalVideoPreviewViewController(
            fileURL: fileURL,
            isMuted: item.isMuted ?? false,
            isLooping: item.isLooping ?? false,
            overlayTitle: MediaTitleStore.displayTitle(for: item)
        )
        present(preview, animated: true)
    }

    private func presentCannotPreview() {
        let alert = UIAlertController(
            title: "Can't Preview",
            message: "This item isn't on this device and isn't available from iCloud. "
                + "Re-add it from Photos to see it here.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
