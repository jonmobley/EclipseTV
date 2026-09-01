//
//  CloudKitSyncEngine+Records.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Record builders + bootstrap enqueue

extension CloudKitSyncEngine {

    /// Builds the CKRecord for a pending save, or nil to skip.
    ///
    /// Captures / imports / PDFs without a local file are skipped rather than
    /// uploaded as metadata-only records.
    func makeRecordToSave(_ recordID: CKRecord.ID) -> CKRecord? {
        if recordID.zoneID != CloudKitSchema.zoneID { return nil }
        let name = recordID.recordName
        let existing = existingRecord(for: recordID)

        if name == CloudKitSchema.backgroundRecordName {
            return makeBackgroundRecordToSave(existing: existing)
        }
        if name == CloudKitSchema.screensaverRecordName {
            return makeScreensaverRecordToSave(existing: existing)
        }
        if name.hasPrefix("eclipse.cameraSettings.") {
            return makeCameraSettingsRecordToSave(name: name, existing: existing)
        }

        if let uuid = UUID(uuidString: name) {
            if let album = LocalAlbumStore.shared.album(id: uuid) {
                return CloudKitRecordMapper.makeShowRecord(
                    from: album,
                    existing: existing,
                    modifiedAt: showModified(id: uuid)
                )
            }
            if let page = WebPageStore.shared.page(id: uuid) {
                return CloudKitRecordMapper.makeWebPageRecord(
                    from: page, existing: existing
                )
            }
            if let show = SlideshowStore.shared.slideshow(id: uuid) {
                return makeSlideshowRecordToSave(show, existing: existing)
            }
            if let item = CountdownStore.shared.countdown(id: uuid) {
                return makeCountdownRecordToSave(item, existing: existing)
            }
            if let item = LivePollStore.shared.poll(id: uuid) {
                return makeLivePollRecordToSave(item, existing: existing)
            }
            if let doc = PDFStore.shared.documents.first(where: { $0.id == uuid }) {
                return makePDFRecordToSave(doc, existing: existing)
            }
            if CameraFrameStore.shared.image(for: uuid) != nil {
                return makeCameraFrameRecordToSave(id: uuid, existing: existing)
            }
            if CameraAlternateStillStore.shared.image(for: uuid) != nil {
                return makeCutawayRecordToSave(id: uuid, existing: existing)
            }
        }

        if let capture = CaptureStore.shared.record(id: name), !capture.isDeleted {
            return makeMediaRecordToSave(capture, existing: existing)
        }
        if let imported = ImportedMediaStore.shared.record(id: name), !imported.isDeleted {
            return makeImportedMediaRecordToSave(imported, existing: existing)
        }
        return nil
    }

    /// Enqueues pending child / tool records. Camera frames, settings, and cutaways
    /// are dirty-only — a blanket re-enqueue would insert records that already exist.
    func enqueueExpandedLocalContent(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        for id in WebPageStore.shared.idsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.webPageRecordID(for: id))
            )
        }
        for id in SlideshowStore.shared.idsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.slideshowRecordID(for: id))
            )
        }
        for id in CountdownStore.shared.idsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.countdownRecordID(for: id))
            )
        }
        for id in LivePollStore.shared.idsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.livePollRecordID(for: id))
            )
        }
        for id in ImportedMediaStore.shared.idsNeedingUpload {
            changes.append(.saveRecord(CloudKitSchema.mediaRecordID(for: id)))
        }
        if LogoStore.shared.hasCustomImage {
            changes.append(.saveRecord(CloudKitSchema.backgroundRecordID))
        }
        if ScreensaverStore.shared.hasCustomMedia {
            changes.append(.saveRecord(CloudKitSchema.screensaverRecordID))
        }
        for id in CameraFrameStore.shared.frameIdsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.cameraFrameRecordID(for: id))
            )
        }
        for orientation in CameraFrameStore.shared.settingsOrientationsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.cameraSettingsRecordID(for: orientation))
            )
        }
        for id in CameraAlternateStillStore.shared.idsNeedingUpload {
            changes.append(
                .saveRecord(CloudKitSchema.cutawayRecordID(for: id))
            )
        }
    }

    // MARK: - Private builders

    func makePDFRecordToSave(_ doc: SavedPDF, existing: CKRecord? = nil) -> CKRecord? {
        guard let assetURL = PDFStore.shared.fileURL(for: doc.id) else {
            logger.notice(
                "Skipping PDF save \(doc.id.uuidString, privacy: .public); file missing"
            )
            return nil
        }
        let resolved = shareRoots.resolve(
            preferredShowId: nil,
            containingShowIds: containingShowIds(itemId: doc.id.uuidString)
        )
        return CloudKitRecordMapper.makePDFRecord(
            from: doc,
            existing: existing,
            assetURL: assetURL,
            showId: resolved.showId,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }

    func makeMediaRecordToSave(
        _ capture: CaptureRecord,
        existing: CKRecord? = nil
    ) -> CKRecord? {
        guard let url = LocalMediaStore.shared.localURL(
            forId: capture.libraryFileName,
            mode: capture.orientation.libraryMode
        ) else {
            logger.notice(
                "Skipping capture save \(capture.id, privacy: .public); file missing"
            )
            return nil
        }
        let resolved = shareRoots.resolve(
            preferredShowId: capture.showId,
            containingShowIds: containingShowIds(itemId: capture.libraryFileName)
        )
        return CloudKitRecordMapper.makeMediaRecord(
            from: capture,
            existing: existing,
            assetURL: url,
            showId: resolved.showId,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }

    func makeImportedMediaRecordToSave(
        _ imported: ImportedMediaRecord,
        existing: CKRecord? = nil
    ) -> CKRecord? {
        guard let url = LocalMediaStore.shared.localURL(
            forId: imported.libraryId,
            mode: imported.orientation.libraryMode
        ) else {
            logger.notice(
                "Skipping import save \(imported.cloudId, privacy: .public); file missing"
            )
            return nil
        }
        let resolved = shareRoots.resolve(
            preferredShowId: imported.showId,
            containingShowIds: containingShowIds(itemId: imported.libraryId)
        )
        return CloudKitRecordMapper.makeImportedMediaRecord(
            from: imported,
            existing: existing,
            assetURL: url,
            showId: resolved.showId,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }

    func makeSlideshowRecordToSave(
        _ show: Slideshow,
        existing: CKRecord? = nil
    ) -> CKRecord {
        let resolved = shareRoots.resolve(
            preferredShowId: show.showId,
            containingShowIds: [show.showId]
        )
        return CloudKitRecordMapper.makeSlideshowRecord(
            from: show,
            existing: existing,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }

    func makeCountdownRecordToSave(
        _ item: ShowCountdown,
        existing: CKRecord? = nil
    ) -> CKRecord {
        let resolved = shareRoots.resolve(
            preferredShowId: item.showId,
            containingShowIds: [item.showId]
        )
        return CloudKitRecordMapper.makeCountdownRecord(
            from: item,
            existing: existing,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }

    func makeLivePollRecordToSave(
        _ item: ShowLivePoll,
        existing: CKRecord? = nil
    ) -> CKRecord {
        let resolved = shareRoots.resolve(
            preferredShowId: item.showId,
            containingShowIds: [item.showId]
        )
        return CloudKitRecordMapper.makeLivePollRecord(
            from: item,
            existing: existing,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }

    func makeBackgroundRecordToSave(existing: CKRecord? = nil) -> CKRecord? {
        guard LogoStore.shared.hasCustomImage,
              let url = LogoStore.shared.customFileURLForSync
        else { return nil }
        return CloudKitRecordMapper.makeBackgroundRecord(
            existing: existing, assetURL: url
        )
    }

    func makeScreensaverRecordToSave(existing: CKRecord? = nil) -> CKRecord? {
        guard let payload = ScreensaverStore.shared.syncPayload else { return nil }
        return CloudKitRecordMapper.makeScreensaverRecord(
            kind: payload.kind,
            existing: existing,
            assetURL: payload.assetURL,
            posterURL: payload.posterURL
        )
    }

    func makeCameraFrameRecordToSave(
        id: UUID,
        existing: CKRecord? = nil
    ) -> CKRecord? {
        guard let frame = CameraFrameStore.shared.frame(id: id),
              FileManager.default.fileExists(
                atPath: CameraFrameStore.shared.fileURL(for: id).path
              )
        else { return nil }
        return CloudKitRecordMapper.makeCameraFrameRecord(
            id: id,
            orientation: frame.orientation,
            createdAt: frame.createdAt,
            existing: existing,
            assetURL: CameraFrameStore.shared.fileURL(for: id)
        )
    }

    func makeCameraSettingsRecordToSave(
        name: String,
        existing: CKRecord? = nil
    ) -> CKRecord? {
        let prefix = "eclipse.cameraSettings."
        guard name.hasPrefix(prefix) else { return nil }
        let raw = String(name.dropFirst(prefix.count))
        let orientation = ExternalOutputOrientation.resolved(fromStored: raw)
        return CloudKitRecordMapper.makeCameraSettingsRecord(
            orientation: orientation,
            enabledIds: Array(CameraFrameStore.shared.enabledIds(for: orientation)),
            selectedId: CameraFrameStore.shared.selectedId(for: orientation),
            existing: existing
        )
    }

    func makeCutawayRecordToSave(
        id: UUID,
        existing: CKRecord? = nil
    ) -> CKRecord? {
        guard let still = CameraAlternateStillStore.shared.stills
            .first(where: { $0.id == id })
        else { return nil }
        let url = CameraAlternateStillStore.shared.fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return CloudKitRecordMapper.makeCutawayRecord(
            id: id,
            createdAt: still.createdAt,
            existing: existing,
            assetURL: url
        )
    }

    func containingShowIds(itemId: String) -> [UUID] {
        LocalAlbumStore.shared.albums
            .filter { $0.itemIds.contains(itemId) }
            .map(\.id)
    }
}
