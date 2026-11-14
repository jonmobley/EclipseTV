//
//  LibraryGridViewController+UnresolvedSync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// Downloads the file behind an iCloud library item onto this device.
    ///
    /// Nothing downloads iCloud media in the background, so this is how an "In iCloud"
    /// tile becomes playable. Tiles follow the store's state ("Downloading…", then the
    /// normal tile), so this only speaks up when the download fails.
    ///
    /// - Parameter id: A library id or cloud id; both stores match either form.
    func downloadFromICloud(id: String, completion: ((Bool) -> Void)? = nil) {
        let downloadId = ImportedMediaStore.shared.record(id: id)?.cloudId
            ?? CaptureStore.shared.record(id: id)?.id
        guard let downloadId else {
            completion?(false)
            return
        }
        Haptics.impactLight()
        EclipseSyncController.shared.backend.downloadAsset(
            id: downloadId,
            progress: nil
        ) { [weak self] result in
            TVLibraryStore.shared.refreshMergedCaptures()
            TVLibraryStore.shared.refreshMergedImports()
            switch result {
            case .success:
                completion?(true)
            case .failure:
                Haptics.error()
                self?.showPresentationToast(
                    "\(UnavailableMediaReason.downloadFailedTitle). Check your connection and try again.",
                    duration: 3.5
                )
                completion?(false)
            }
        }
    }
}

extension LibraryGridViewController {

    /// Starts an on-demand CloudKit download when the user taps a placeholder tile.
    func requestUnresolvedDownloadIfNeeded(id: String) {
        downloadFromICloud(id: id) { [weak self] _ in
            self?.collectionView.reloadData()
        }
    }
}

extension UIViewController {

    /// "Download from iCloud", or a greyed "Downloading from iCloud…" while it runs.
    func iCloudDownloadAction(
        for item: LibraryItemDTO,
        reason: UnavailableMediaReason,
        download: @escaping () -> Void
    ) -> UIAction {
        let isDownloading = reason == .downloading
        return UIAction(
            title: isDownloading
                ? UnavailableMediaReason.downloadingTitle
                : UnavailableMediaReason.downloadTitle,
            image: UIImage(systemName: "icloud.and.arrow.down"),
            attributes: isDownloading ? .disabled : []
        ) { _ in download() }
    }
}
