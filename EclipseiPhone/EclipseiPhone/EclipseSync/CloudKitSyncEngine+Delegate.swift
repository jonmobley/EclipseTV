//
//  CloudKitSyncEngine+Delegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncEngine: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persistEngineState(update.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == CloudKitSchema.zoneID {
                // Local content is the user's — never delete it because the server
                // dropped the zone. Recreate and push everything back up.
                logger.warning("Library zone deleted remotely; recreating")
                recoverFromZoneLoss()
            }

        case .fetchedRecordZoneChanges(let changes):
            await applyFetchedModifications(changes.modifications.map(\.record))
            isApplyingRemote = true
            for deletion in changes.deletions {
                EclipseSyncController.shared.applyRemoteDeletion(
                    recordName: deletion.recordID.recordName
                )
            }
            isApplyingRemote = false

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent)

        case .sentDatabaseChanges:
            break

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        var mutableRecordMap: [CKRecord.ID: CKRecord] = [:]
        for change in changes {
            if case .saveRecord(let recordID) = change,
               let record = makeRecordToSave(recordID) {
                mutableRecordMap[recordID] = record
            } else if case .saveRecord(let recordID) = change {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }
        let recordMap = mutableRecordMap
        return await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: changes
        ) { recordID in
            recordMap[recordID]
        }
    }

    // MARK: - Fetch apply

    private func applyFetchedModifications(_ records: [CKRecord]) async {
        isApplyingRemote = true
        EclipseSyncController.shared.isApplyingRemote = true
        defer {
            isApplyingRemote = false
            EclipseSyncController.shared.isApplyingRemote = false
        }
        for record in records {
            switch record.recordType {
            case CloudKitSchema.RecordType.show:
                applyRemoteShow(record)
            case CloudKitSchema.RecordType.mediaItem:
                if let capture = CloudKitRecordMapper.capture(from: record) {
                    CaptureStore.shared.applyRemote(capture)
                }
            case CloudKitSchema.RecordType.pdfDoc:
                if let doc = CloudKitRecordMapper.savedPDF(from: record) {
                    PDFStore.shared.applyRemote(
                        doc,
                        assetURL: CloudKitRecordMapper.pdfAssetURL(from: record)
                    )
                }
            default:
                break
            }
        }
    }

    private func applyRemoteShow(_ record: CKRecord) {
        guard let remote = CloudKitRecordMapper.album(from: record) else { return }
        let remoteModified = CloudKitRecordMapper.showModifiedAt(from: record)
        if let local = LocalAlbumStore.shared.album(id: remote.id) {
            let localModified = showModified(id: local.id)
            let merged = CloudKitConflictResolver.mergeShows(
                local: local,
                localModified: localModified,
                remote: remote,
                remoteModified: remoteModified
            )
            LocalAlbumStore.shared.applySynced(
                merged,
                modifiedAt: max(localModified, remoteModified)
            )
        } else {
            LocalAlbumStore.shared.applySynced(remote, modifiedAt: remoteModified)
        }
    }

    // MARK: - Send helpers

    /// Builds the CKRecord for a pending save, or nil to skip.
    ///
    /// Captures and PDFs without a local file are skipped rather than uploaded as
    /// metadata-only records — those look Synced here and are undownloadable elsewhere.
    func makeRecordToSave(_ recordID: CKRecord.ID) -> CKRecord? {
        if recordID.zoneID != CloudKitSchema.zoneID { return nil }
        if let uuid = UUID(uuidString: recordID.recordName) {
            if let album = LocalAlbumStore.shared.album(id: uuid) {
                return CloudKitRecordMapper.makeShowRecord(
                    from: album,
                    modifiedAt: showModified(id: uuid)
                )
            }
            if let doc = PDFStore.shared.documents.first(where: { $0.id == uuid }) {
                guard let assetURL = PDFStore.shared.fileURL(for: uuid) else {
                    logger.notice(
                        "Skipping PDF save \(uuid.uuidString, privacy: .public); file missing"
                    )
                    return nil
                }
                return CloudKitRecordMapper.makePDFRecord(
                    from: doc,
                    assetURL: assetURL,
                    showId: LocalAlbumStore.shared.albums.first {
                        $0.itemIds.contains(uuid.uuidString)
                    }?.id
                )
            }
        }
        if let capture = CaptureStore.shared.record(id: recordID.recordName),
           !capture.isDeleted {
            guard let url = LocalMediaStore.shared.localURL(
                forId: capture.libraryFileName,
                mode: capture.orientation.libraryMode
            ) else {
                logger.notice(
                    "Skipping capture save \(capture.id, privacy: .public); file missing"
                )
                return nil
            }
            return CloudKitRecordMapper.makeMediaRecord(
                from: capture,
                assetURL: url
            )
        }
        return nil
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        for saved in sent.savedRecords {
            switch saved.recordType {
            case CloudKitSchema.RecordType.mediaItem:
                CaptureStore.shared.setSyncState(id: saved.recordID.recordName, .synced)
            case CloudKitSchema.RecordType.pdfDoc:
                if let uuid = UUID(uuidString: saved.recordID.recordName) {
                    PDFStore.shared.markSynced(id: uuid)
                }
            default:
                break
            }
            account.clearQuotaPause()
        }
        var didRecoverZone = false
        for failed in sent.failedRecordSaves {
            let code = failed.error.code
            switch CloudKitSaveFailurePolicy.action(for: code) {
            case .holdForQuota:
                holdForQuota(failed.record.recordID)
            case .mergeAndRequeue:
                mergeConflictAndRequeue(record: failed.record, error: failed.error)
            case .recreateZone:
                if !didRecoverZone {
                    didRecoverZone = true
                    recoverFromZoneLoss()
                }
            case .dropPendingChange:
                engine?.state.remove(pendingRecordZoneChanges: [
                    .saveRecord(failed.record.recordID)
                ])
                logger.error(
                    "Dropped pending save for unknown item \(failed.record.recordID.recordName, privacy: .public)"
                )
            case .retryHandledByEngine:
                logger.notice(
                    "Save retry deferred to CKSyncEngine for \(failed.record.recordID.recordName, privacy: .public): \(failed.error.localizedDescription)"
                )
            case .logOnly:
                logger.error(
                    "Save failed \(failed.record.recordID.recordName, privacy: .public): \(failed.error.localizedDescription)"
                )
            }
        }
        for id in sent.deletedRecordIDs {
            CaptureStore.shared.purge(id: id.recordName)
        }
    }

    /// Applies the server's winning record, then re-queues our (merged) local copy.
    private func mergeConflictAndRequeue(record: CKRecord, error: CKError) {
        guard let server = error.serverRecord else {
            logger.error(
                "serverRecordChanged without server record for \(record.recordID.recordName, privacy: .public)"
            )
            return
        }
        isApplyingRemote = true
        EclipseSyncController.shared.isApplyingRemote = true
        defer {
            isApplyingRemote = false
            EclipseSyncController.shared.isApplyingRemote = false
        }
        switch server.recordType {
        case CloudKitSchema.RecordType.show:
            applyRemoteShow(server)
            if let uuid = UUID(uuidString: server.recordID.recordName) {
                scheduleShowSave(id: uuid)
            }
        case CloudKitSchema.RecordType.pdfDoc:
            if let doc = CloudKitRecordMapper.savedPDF(from: server) {
                PDFStore.shared.applyRemote(
                    doc,
                    assetURL: CloudKitRecordMapper.pdfAssetURL(from: server)
                )
                schedulePDFSave(id: doc.id)
            }
        case CloudKitSchema.RecordType.mediaItem:
            if let capture = CloudKitRecordMapper.capture(from: server) {
                CaptureStore.shared.applyRemote(capture)
                scheduleCaptureSave(id: capture.id)
            }
        default:
            logger.error(
                "Unhandled conflict type \(server.recordType, privacy: .public)"
            )
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signOut, .switchAccounts:
            engine = nil
            await account.refresh()
        case .signIn:
            await bootstrapEngineIfPossiblePublic()
        @unknown default:
            await account.refresh()
        }
    }
}
