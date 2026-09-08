//
//  LibraryGridViewController+UnresolvedSync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Starts an on-demand CloudKit download when the user taps a placeholder tile.
    func requestUnresolvedDownloadIfNeeded(id: String) {
        // A placeholder's id is either a cloud id or a library filename, and both
        // stores already match on either, so one lookup each covers both forms.
        let downloadId: String? = {
            if let imported = ImportedMediaStore.shared.record(id: id) {
                return imported.cloudId
            }
            return CaptureStore.shared.record(id: id)?.id
        }()
        guard let downloadId else {
            collectionView.reloadData()
            return
        }
        EclipseSyncController.shared.backend.downloadAsset(
            id: downloadId,
            progress: nil
        ) { [weak self] result in
            switch result {
            case .success:
                TVLibraryStore.shared.refreshMergedCaptures()
                TVLibraryStore.shared.refreshMergedImports()
                self?.collectionView.reloadData()
            case .failure:
                self?.collectionView.reloadData()
            }
        }
    }
}
