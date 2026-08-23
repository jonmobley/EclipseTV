//
//  CloudKitRecordMapper.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// Maps between local Show / capture models and CloudKit records.
enum CloudKitRecordMapper {

    // MARK: - Show

    /// Builds a Show `CKRecord` (share root). Does not attach a share.
    static func makeShowRecord(
        from album: LocalAlbum,
        existing: CKRecord? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.show,
            recordID: CloudKitSchema.showRecordID(for: album.id)
        )
        record[CloudKitSchema.ShowKey.name] = album.name as CKRecordValue
        record[CloudKitSchema.ShowKey.orientation] = album.orientation.rawValue as CKRecordValue
        record[CloudKitSchema.ShowKey.itemIds] = album.itemIds as CKRecordValue
        if let surface = album.surfaceIds {
            record[CloudKitSchema.ShowKey.surfaceIds] = surface as CKRecordValue
        } else {
            record[CloudKitSchema.ShowKey.surfaceIds] = nil
        }
        if let cover = album.coverId {
            record[CloudKitSchema.ShowKey.coverId] = cover as CKRecordValue
        } else {
            record[CloudKitSchema.ShowKey.coverId] = nil
        }
        record[CloudKitSchema.ShowKey.createdAt] = album.createdAt as CKRecordValue
        record[CloudKitSchema.ShowKey.modifiedAt] = modifiedAt as CKRecordValue
        record[CloudKitSchema.ShowKey.previewsWhenDisconnected] =
            album.previewsWhenDisconnected as CKRecordValue
        return record
    }

    /// Local album from a Show record.
    static func album(from record: CKRecord) -> LocalAlbum? {
        guard record.recordType == CloudKitSchema.RecordType.show,
              let uuid = UUID(uuidString: record.recordID.recordName),
              let name = record[CloudKitSchema.ShowKey.name] as? String
        else { return nil }
        let itemIds = (record[CloudKitSchema.ShowKey.itemIds] as? [String]) ?? []
        let surfaceIds = record[CloudKitSchema.ShowKey.surfaceIds] as? [String]
        let coverId = record[CloudKitSchema.ShowKey.coverId] as? String
        let rawOrientation = record[CloudKitSchema.ShowKey.orientation] as? String
        let orientation = ExternalOutputOrientation.resolved(fromStored: rawOrientation)
        let createdAt = (record[CloudKitSchema.ShowKey.createdAt] as? Date) ?? Date()
        let previewsWhenDisconnected =
            (record[CloudKitSchema.ShowKey.previewsWhenDisconnected] as? Bool) ?? false
        return LocalAlbum(
            id: uuid,
            name: UserDisplayName.clamp(name),
            itemIds: itemIds,
            coverId: coverId,
            orientation: orientation,
            createdAt: createdAt,
            surfaceIds: surfaceIds,
            previewsWhenDisconnected: previewsWhenDisconnected
        )
    }

    static func showModifiedAt(from record: CKRecord) -> Date {
        (record[CloudKitSchema.ShowKey.modifiedAt] as? Date)
            ?? record.modificationDate
            ?? Date.distantPast
    }

    // MARK: - MediaItem

    /// Builds a MediaItem record. Always writes `showId`; sets `parent` only
    /// when `attachAsShareChild` is true (the Show is a `CKShare` root).
    static func makeMediaRecord(
        from capture: CaptureRecord,
        existing: CKRecord? = nil,
        assetURL: URL? = nil,
        modifiedAt: Date = Date(),
        showId: UUID? = nil,
        attachAsShareChild: Bool = false
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.mediaItem,
            recordID: CloudKitSchema.mediaRecordID(for: capture.id)
        )
        record[CloudKitSchema.MediaKey.isVideo] = capture.isVideo as CKRecordValue
        record[CloudKitSchema.MediaKey.duration] = capture.duration as CKRecordValue
        record[CloudKitSchema.MediaKey.capturedAt] = capture.capturedAt as CKRecordValue
        record[CloudKitSchema.MediaKey.orientation] =
            capture.orientation.rawValue as CKRecordValue
        record[CloudKitSchema.MediaKey.fileExtension] =
            capture.fileExtension as CKRecordValue
        record[CloudKitSchema.MediaKey.modifiedAt] = modifiedAt as CKRecordValue
        if let hash = capture.contentHash {
            record[CloudKitSchema.MediaKey.contentHash] = hash as CKRecordValue
        }
        applyShowLink(
            to: record,
            showId: showId ?? capture.showId,
            showIdKey: CloudKitSchema.MediaKey.showId,
            attachAsShareChild: attachAsShareChild
        )
        if let assetURL {
            record[CloudKitSchema.MediaKey.asset] = CKAsset(fileURL: assetURL)
        }
        return record
    }

    /// Writes `showId` as a regular field. Sets `parent` only for share roots.
    static func applyShowLink(
        to record: CKRecord,
        showId: UUID?,
        showIdKey: String,
        attachAsShareChild: Bool
    ) {
        guard let showId else {
            record[showIdKey] = nil
            record.parent = nil
            return
        }
        record[showIdKey] = showId.uuidString as CKRecordValue
        if attachAsShareChild {
            record.parent = CKRecord.Reference(
                recordID: CloudKitSchema.showRecordID(for: showId),
                action: .none
            )
        } else {
            record.parent = nil
        }
    }

    /// Capture from a MediaItem record (asset not downloaded here).
    static func capture(from record: CKRecord) -> CaptureRecord? {
        guard record.recordType == CloudKitSchema.RecordType.mediaItem else { return nil }
        let id = record.recordID.recordName
        let isVideo = (record[CloudKitSchema.MediaKey.isVideo] as? Bool) ?? false
        let duration = (record[CloudKitSchema.MediaKey.duration] as? Double) ?? 0
        let capturedAt = (record[CloudKitSchema.MediaKey.capturedAt] as? Date) ?? Date()
        let rawOrientation = record[CloudKitSchema.MediaKey.orientation] as? String
        let orientation = ExternalOutputOrientation.resolved(fromStored: rawOrientation)
        let ext = (record[CloudKitSchema.MediaKey.fileExtension] as? String)
            ?? (isVideo ? "mov" : "jpg")
        let showRaw = record[CloudKitSchema.MediaKey.showId] as? String
        let showId = showRaw.flatMap(UUID.init(uuidString:))
        let hash = record[CloudKitSchema.MediaKey.contentHash] as? String
        return CaptureRecord(
            id: id,
            isVideo: isVideo,
            duration: duration,
            capturedAt: capturedAt,
            orientation: orientation,
            showId: showId,
            contentHash: hash,
            fileExtension: ext,
            syncState: .remoteOnly
        )
    }

    static func mediaAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.MediaKey.asset] as? CKAsset)?.fileURL
    }
}
