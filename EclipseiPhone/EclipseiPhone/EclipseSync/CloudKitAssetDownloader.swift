//
//  CloudKitAssetDownloader.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import os.log

/// On-demand fetch of a MediaItem `CKAsset` into the local Captures directory.
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
    /// Callers waiting per capture id, so a repeat request joins the fetch already in
    /// flight. Dropping the repeat instead would strand its caller: a tapped thumbnail
    /// waits on this completion to dismiss its progress alert, and a completion that
    /// never arrives leaves that alert on screen for good.
    private var waiters: [String: [Waiter]] = [:]

    init(container: CKContainer) {
        self.container = container
    }

    /// Fetches the MediaItem record and copies its asset into Captures storage.
    ///
    /// Repeat requests for the same id (a double-tapped thumbnail, a retry racing a
    /// scheduled fetch) share the one network round trip and all hear back from it.
    func download(
        id: String,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        guard let capture = CaptureStore.shared.record(id: id) else {
            completion(.failure(DownloadError.notFound))
            return
        }
        let libraryId = capture.libraryFileName
        let mode = capture.orientation.libraryMode
        if let existing = LocalMediaStore.shared.localURL(forId: libraryId, mode: mode) {
            CaptureStore.shared.setSyncState(id: capture.id, .synced)
            completion(.success(existing))
            return
        }
        let waiter = Waiter(progress: progress, completion: completion)
        if waiters[capture.id] != nil {
            waiters[capture.id]?.append(waiter)
            return
        }
        waiters[capture.id] = [waiter]
        CaptureStore.shared.setSyncState(id: capture.id, .downloading)
        report(0, for: capture.id)

        let recordID = CloudKitSchema.mediaRecordID(for: capture.id)
        // Private DB first (owned captures); shared DB for accepted Share participants.
        fetchRecord(recordID, from: container.privateCloudDatabase) { [weak self] privateResult in
            Task { @MainActor in
                guard let self else { return }
                switch privateResult {
                case .success(let record):
                    self.storeAsset(
                        from: record, captureId: capture.id, libraryId: libraryId, mode: mode
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
                                    captureId: capture.id,
                                    libraryId: libraryId,
                                    mode: mode
                                )
                            case .failure(let error):
                                CaptureStore.shared.setSyncState(id: capture.id, .remoteOnly)
                                self.logger.error(
                                    "Fetch failed: \(error.localizedDescription)"
                                )
                                self.finish(capture.id, .failure(error))
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
        captureId: String,
        libraryId: String,
        mode: EclipseShareProtocol.LibraryMode
    ) {
        guard let assetURL = CloudKitRecordMapper.mediaAssetURL(from: record) else {
            CaptureStore.shared.setSyncState(id: captureId, .remoteOnly)
            finish(captureId, .failure(DownloadError.noAsset))
            return
        }
        do {
            report(0.5, for: captureId)
            try LocalMediaStore.shared.storeSynchronously(
                fileURL: assetURL,
                forId: libraryId,
                mode: mode,
                provenance: .captured
            )
            report(1, for: captureId)
            CaptureStore.shared.setSyncState(id: captureId, .synced)
            if let url = LocalMediaStore.shared.localURL(forId: libraryId, mode: mode) {
                finish(captureId, .success(url))
            } else {
                finish(captureId, .failure(DownloadError.noAsset))
            }
        } catch {
            CaptureStore.shared.setSyncState(id: captureId, .remoteOnly)
            finish(captureId, .failure(error))
        }
    }

    // MARK: - Waiters

    /// Reports `fraction` to everyone waiting on `id`.
    private func report(_ fraction: Double, for id: String) {
        waiters[id]?.forEach { $0.progress?(fraction) }
    }

    /// Delivers `result` to everyone waiting on `id`, then clears the queue.
    ///
    /// Clears first so a completion that starts another download for the same id sees
    /// no stale in-flight entry.
    private func finish(_ id: String, _ result: Result<URL, Error>) {
        let pending = waiters.removeValue(forKey: id) ?? []
        for waiter in pending {
            waiter.completion(result)
        }
    }
}
