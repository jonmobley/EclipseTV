//
//  CloudKitSyncEngine+Apply.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Remote apply

extension CloudKitSyncEngine {

    /// Applies fetched records. Children (media / pages / slideshows) first, then Shows.
    func applyFetchedModifications(_ records: [CKRecord]) async {
        let wasApplying = isApplyingRemote
        let controllerWasApplying = EclipseSyncController.shared.isApplyingRemote
        isApplyingRemote = true
        EclipseSyncController.shared.isApplyingRemote = true
        defer {
            isApplyingRemote = wasApplying
            EclipseSyncController.shared.isApplyingRemote = controllerWasApplying
        }
        let shows = records.filter { $0.recordType == CloudKitSchema.RecordType.show }
        let children = records.filter { $0.recordType != CloudKitSchema.RecordType.show }
        for record in children {
            rememberLastKnown(record)
            applyChildRecord(record)
        }
        for record in shows {
            rememberLastKnown(record)
            applyRemoteShow(record)
        }
    }

    func applyChildRecord(_ record: CKRecord) {
        switch record.recordType {
        case CloudKitSchema.RecordType.mediaItem:
            applyRemoteMedia(record)
        case CloudKitSchema.RecordType.pdfDoc:
            if let doc = CloudKitRecordMapper.savedPDF(from: record) {
                PDFStore.shared.applyRemote(
                    doc,
                    assetURL: CloudKitRecordMapper.pdfAssetURL(from: record)
                )
            }
        case CloudKitSchema.RecordType.webPage:
            if let page = CloudKitRecordMapper.webPage(from: record) {
                WebPageStore.shared.applyRemote(page)
            }
        case CloudKitSchema.RecordType.slideshow:
            if let show = CloudKitRecordMapper.slideshow(from: record) {
                SlideshowStore.shared.applyRemote(show)
            }
        case CloudKitSchema.RecordType.countdown:
            if let item = CloudKitRecordMapper.countdown(from: record) {
                CountdownStore.shared.applyRemote(item)
            }
        case CloudKitSchema.RecordType.livePoll:
            if let item = CloudKitRecordMapper.livePoll(from: record) {
                LivePollStore.shared.applyRemote(item)
            }
        case CloudKitSchema.RecordType.background:
            LogoStore.shared.applyRemote(
                assetURL: CloudKitRecordMapper.backgroundAssetURL(from: record)
            )
        case CloudKitSchema.RecordType.screensaver:
            ScreensaverStore.shared.applyRemote(
                kind: CloudKitRecordMapper.screensaverKind(from: record),
                assetURL: CloudKitRecordMapper.screensaverAssetURL(from: record),
                posterURL: CloudKitRecordMapper.screensaverPosterURL(from: record)
            )
        case CloudKitSchema.RecordType.cameraFrame:
            applyRemoteCameraFrame(record)
        case CloudKitSchema.RecordType.cameraSettings:
            applyRemoteCameraSettings(record)
        case CloudKitSchema.RecordType.cutawayStill:
            applyRemoteCutaway(record)
        default:
            break
        }
    }

    func applyRemoteShow(_ record: CKRecord) {
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
            let winning = max(localModified, remoteModified)
            LocalAlbumStore.shared.applySynced(merged, modifiedAt: winning)
            rememberShowModified(id: remote.id, at: winning)
        } else {
            LocalAlbumStore.shared.applySynced(remote, modifiedAt: remoteModified)
            rememberShowModified(id: remote.id, at: remoteModified)
        }
        learnShareRoot(from: record)
    }

    func applyRemoteMedia(_ record: CKRecord) {
        if CloudKitRecordMapper.isImportedMedia(record),
           let imported = CloudKitRecordMapper.importedMedia(from: record) {
            ImportedMediaStore.shared.applyRemote(imported)
            CloudKitRecordMapper.applyRemoteMediaPrefs(
                from: record, libraryId: imported.libraryId
            )
            TVLibraryStore.shared.refreshMergedImports()
            adoptFetchedAsset(
                from: record,
                libraryId: imported.libraryId,
                mode: imported.orientation.libraryMode,
                provenance: .imported
            ) {
                ImportedMediaStore.shared.setSyncState(id: imported.cloudId, .synced)
                TVLibraryStore.shared.refreshMergedImports()
            }
            return
        }
        if let capture = CloudKitRecordMapper.capture(from: record) {
            CaptureStore.shared.applyRemote(capture)
            CloudKitRecordMapper.applyRemoteMediaPrefs(
                from: record, libraryId: capture.libraryFileName
            )
            TVLibraryStore.shared.refreshMergedCaptures()
            adoptFetchedAsset(
                from: record,
                libraryId: capture.libraryFileName,
                mode: capture.orientation.libraryMode,
                provenance: .captured
            ) {
                CaptureStore.shared.setSyncState(id: capture.id, .synced)
                TVLibraryStore.shared.refreshMergedCaptures()
            }
        }
    }

    /// Keeps the asset bytes that arrived with `record`, when policy allows.
    ///
    /// The copy runs off the main thread because a full-resolution video can be
    /// hundreds of megabytes. The `CKAsset` is held across it so CloudKit's staged
    /// file — which the system purges on its own schedule — outlives the copy.
    private func adoptFetchedAsset(
        from record: CKRecord,
        libraryId: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance,
        onStored: @escaping () -> Void
    ) {
        let asset = record[CloudKitSchema.MediaKey.asset] as? CKAsset
        guard let assetURL = CloudKitAssetAdoptionPolicy.adoptableURL(
            asset?.fileURL,
            hasLocalBytes: LocalMediaStore.shared.hasMedia(forId: libraryId, mode: mode),
            wasEvictedByUser: evictedMedia.contains(record.recordID.recordName)
        ) else { return }
        LocalMediaStore.shared.store(
            fileURL: assetURL,
            forId: libraryId,
            mode: mode,
            provenance: provenance
        ) { stored in
            withExtendedLifetime(asset) {
                guard stored else { return }
                onStored()
            }
        }
    }

    private func applyRemoteCameraFrame(_ record: CKRecord) {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let orientation = CloudKitRecordMapper.cameraFrameOrientation(from: record),
              let assetURL = CloudKitRecordMapper.cameraFrameAssetURL(from: record)
        else { return }
        CameraFrameStore.shared.applyRemote(
            id: uuid,
            orientation: orientation,
            createdAt: CloudKitRecordMapper.cameraFrameCreatedAt(from: record),
            assetURL: assetURL
        )
    }

    private func applyRemoteCameraSettings(_ record: CKRecord) {
        guard let orientation = CloudKitRecordMapper.cameraSettingsOrientation(from: record)
        else { return }
        CameraFrameStore.shared.applyRemoteSettings(
            orientation: orientation,
            enabledIds: CloudKitRecordMapper.cameraSettingsEnabledIds(from: record),
            selectedId: CloudKitRecordMapper.cameraSettingsSelectedId(from: record)
        )
    }

    private func applyRemoteCutaway(_ record: CKRecord) {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let assetURL = CloudKitRecordMapper.cutawayAssetURL(from: record)
        else { return }
        CameraAlternateStillStore.shared.applyRemote(
            id: uuid,
            createdAt: CloudKitRecordMapper.cutawayCreatedAt(from: record),
            assetURL: assetURL
        )
    }

    /// Marks sent records synced and caches them for tagged updates.
    func noteSavedRecord(_ saved: CKRecord) {
        rememberLastKnown(saved)
        markLocalRecordSynced(saved)
        account.clearQuotaPause()
    }
}
