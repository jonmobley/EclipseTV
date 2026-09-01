//
//  CloudKitAssetDownloader.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import os.log

/// On-demand fetch of a MediaItem `CKAsset` into Captures or LocalMedia.
@MainActor
final class CloudKitAssetDownloader {

    enum DownloadError: LocalizedError {
        case notFound
        case noAsset
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notFound: return "This item is no longer in iCloud."
            case .noAsset: return "No downloadable file is attached to this item."
            case .cancelled: return "Download cancelled."
            }
        }
    }

    /// One caller waiting on a download.
    private struct Waiter {
        let progress: (@Sendable (Double) -> Void)?
        let completion: @MainActor (Result<URL, Error>) -> Void
    }

    private let container: CKContainer
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CloudKitAssetDownloader"
    )
    private var waiters: [String: [Waiter]] = [:]

    init(container: CKContainer) {
        self.container = container
    }

    /// Fetches the MediaItem record and copies its asset into local storage.
    func download(
        id: String,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        if let capture = CaptureStore.shared.record(id: id) {
            downloadCapture(
                capture, progress: progress, completion: completion
            )
            return
        }
        if let imported = ImportedMediaStore.shared.record(id: id) {
            downloadImport(
                imported, progress: progress, completion: completion
            )
            return
        }
        completion(.failure(DownloadError.notFound))
    }

    private func downloadCapture(
        _ capture: CaptureRecord,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let libraryId = capture.libraryFileName
        let mode = capture.orientation.libraryMode
        if let existing = LocalMediaStore.shared.localURL(forId: libraryId, mode: mode) {
            CaptureStore.shared.setSyncState(id: capture.id, .synced)
            completion(.success(existing))
            return
        }
        beginFetch(
            cloudId: capture.id,
            libraryId: libraryId,
            mode: mode,
            provenance: .captured,
            markDownloading: { CaptureStore.shared.setSyncState(id: capture.id, .downloading) },
            markRemoteOnly: { CaptureStore.shared.setSyncState(id: capture.id, .remoteOnly) },
            markSynced: { CaptureStore.shared.setSyncState(id: capture.id, .synced) },
            progress: progress,
            completion: completion
        )
    }

    private func downloadImport(
        _ imported: ImportedMediaRecord,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let libraryId = imported.libraryId
        let mode = imported.orientation.libraryMode
        if let existing = LocalMediaStore.shared.localURL(forId: libraryId, mode: mode) {
            ImportedMediaStore.shared.setSyncState(id: imported.cloudId, .synced)
            completion(.success(existing))
            return
        }
        beginFetch(
            cloudId: imported.cloudId,
            libraryId: libraryId,
            mode: mode,
            provenance: .imported,
            markDownloading: {
                ImportedMediaStore.shared.setSyncState(id: imported.cloudId, .downloading)
            },
            markRemoteOnly: {
                ImportedMediaStore.shared.setSyncState(id: imported.cloudId, .remoteOnly)
            },
            markSynced: {
                ImportedMediaStore.shared.setSyncState(id: imported.cloudId, .synced)
            },
            progress: progress,
            completion: completion
        )
    }

    private func beginFetch(
        cloudId: String,
        libraryId: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance,
        markDownloading: () -> Void,
        markRemoteOnly: @escaping () -> Void,
        markSynced: @escaping () -> Void,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let waiter = Waiter(progress: progress, completion: completion)
        if waiters[cloudId] != nil {
            waiters[cloudId]?.append(waiter)
            return
        }
        waiters[cloudId] = [waiter]
        markDownloading()
        report(0, for: cloudId)

        let recordID = CloudKitSchema.mediaRecordID(for: cloudId)
        fetchRecord(recordID, from: container.privateCloudDatabase) { [weak self] privateResult in
            Task { @MainActor in
                guard let self else { return }
                switch privateResult {
                case .success(let record):
                    self.storeAsset(
                        from: record,
                        cloudId: cloudId,
                        libraryId: libraryId,
                        mode: mode,
                        provenance: provenance,
                        markRemoteOnly: markRemoteOnly,
                        markSynced: markSynced
                    )
                case .failure:
                    self.fetchRecord(
                        recordID,
                        from: self.container.sharedCloudDatabase
                    ) { [weak self] shared in
                        Task { @MainActor in
                            guard let self else { return }
                            switch shared {
                            case .success(let record):
                                self.storeAsset(
                                    from: record,
                                    cloudId: cloudId,
                                    libraryId: libraryId,
                                    mode: mode,
                                    provenance: provenance,
                                    markRemoteOnly: markRemoteOnly,
                                    markSynced: markSynced
                                )
                            case .failure(let error):
                                markRemoteOnly()
                                self.logger.error(
                                    "Fetch failed: \(error.localizedDescription)"
                                )
                                self.finish(cloudId, .failure(error))
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchRecord(
        _ recordID: CKRecord.ID,
        from database: CKDatabase,
        completion: @escaping (Result<CKRecord, Error>) -> Void
    ) {
        database.fetch(withRecordID: recordID) { record, error in
            if let record {
                completion(.success(record))
            } else {
                completion(.failure(error ?? DownloadError.notFound))
            }
        }
    }

    private func storeAsset(
        from record: CKRecord,
        cloudId: String,
        libraryId: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance,
        markRemoteOnly: () -> Void,
        markSynced: () -> Void
    ) {
        guard let assetURL = CloudKitRecordMapper.mediaAssetURL(from: record) else {
            markRemoteOnly()
            finish(cloudId, .failure(DownloadError.noAsset))
            return
        }
        do {
            report(0.5, for: cloudId)
            try LocalMediaStore.shared.storeSynchronously(
                fileURL: assetURL,
                forId: libraryId,
                mode: mode,
                provenance: provenance
            )
            report(1, for: cloudId)
            markSynced()
            if let url = LocalMediaStore.shared.localURL(forId: libraryId, mode: mode) {
                finish(cloudId, .success(url))
            } else {
                finish(cloudId, .failure(DownloadError.noAsset))
            }
        } catch {
            markRemoteOnly()
            finish(cloudId, .failure(error))
        }
    }

    private func report(_ fraction: Double, for id: String) {
        waiters[id]?.forEach { $0.progress?(fraction) }
    }

    private func finish(_ id: String, _ result: Result<URL, Error>) {
        let pending = waiters.removeValue(forKey: id) ?? []
        for waiter in pending {
            waiter.completion(result)
        }
    }
}
