//
//  CloudKitRecordMapper+Tools.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Account-global tool libraries

extension CloudKitRecordMapper {

    /// Singleton Background record with optional custom JPEG asset.
    static func makeBackgroundRecord(
        existing: CKRecord? = nil,
        assetURL: URL? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.background,
            recordID: CloudKitSchema.backgroundRecordID
        )
        record[CloudKitSchema.BackgroundKey.modifiedAt] = modifiedAt as CKRecordValue
        if let assetURL {
            record[CloudKitSchema.BackgroundKey.asset] = CKAsset(fileURL: assetURL)
        } else {
            record[CloudKitSchema.BackgroundKey.asset] = nil
        }
        return record
    }

    static func backgroundAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.BackgroundKey.asset] as? CKAsset)?.fileURL
    }

    /// Singleton Screensaver record with kind + optional media/poster assets.
    static func makeScreensaverRecord(
        kind: String?,
        existing: CKRecord? = nil,
        assetURL: URL? = nil,
        posterURL: URL? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.screensaver,
            recordID: CloudKitSchema.screensaverRecordID
        )
        record[CloudKitSchema.ScreensaverKey.modifiedAt] = modifiedAt as CKRecordValue
        if let kind {
            record[CloudKitSchema.ScreensaverKey.kind] = kind as CKRecordValue
        } else {
            record[CloudKitSchema.ScreensaverKey.kind] = nil
        }
        if let assetURL {
            record[CloudKitSchema.ScreensaverKey.asset] = CKAsset(fileURL: assetURL)
        } else {
            record[CloudKitSchema.ScreensaverKey.asset] = nil
        }
        if let posterURL {
            record[CloudKitSchema.ScreensaverKey.poster] = CKAsset(fileURL: posterURL)
        } else {
            record[CloudKitSchema.ScreensaverKey.poster] = nil
        }
        return record
    }

    static func screensaverKind(from record: CKRecord) -> String? {
        record[CloudKitSchema.ScreensaverKey.kind] as? String
    }

    static func screensaverAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.ScreensaverKey.asset] as? CKAsset)?.fileURL
    }

    static func screensaverPosterURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.ScreensaverKey.poster] as? CKAsset)?.fileURL
    }

    /// Camera frame PNG record.
    static func makeCameraFrameRecord(
        id: UUID,
        orientation: ExternalOutputOrientation,
        createdAt: Date,
        existing: CKRecord? = nil,
        assetURL: URL? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.cameraFrame,
            recordID: CloudKitSchema.cameraFrameRecordID(for: id)
        )
        record[CloudKitSchema.CameraFrameKey.orientation] =
            orientation.rawValue as CKRecordValue
        record[CloudKitSchema.CameraFrameKey.createdAt] = createdAt as CKRecordValue
        record[CloudKitSchema.CameraFrameKey.modifiedAt] = modifiedAt as CKRecordValue
        if let assetURL {
            record[CloudKitSchema.CameraFrameKey.asset] = CKAsset(fileURL: assetURL)
        }
        return record
    }

    static func cameraFrameAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.CameraFrameKey.asset] as? CKAsset)?.fileURL
    }

    static func cameraFrameOrientation(from record: CKRecord) -> ExternalOutputOrientation? {
        guard let raw = record[CloudKitSchema.CameraFrameKey.orientation] as? String
        else { return nil }
        return ExternalOutputOrientation.resolved(fromStored: raw)
    }

    static func cameraFrameCreatedAt(from record: CKRecord) -> Date {
        (record[CloudKitSchema.CameraFrameKey.createdAt] as? Date) ?? Date()
    }

    /// Per-orientation camera ribbon settings.
    static func makeCameraSettingsRecord(
        orientation: ExternalOutputOrientation,
        enabledIds: [UUID],
        selectedId: UUID?,
        existing: CKRecord? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.cameraSettings,
            recordID: CloudKitSchema.cameraSettingsRecordID(for: orientation)
        )
        record[CloudKitSchema.CameraSettingsKey.orientation] =
            orientation.rawValue as CKRecordValue
        record[CloudKitSchema.CameraSettingsKey.enabledIds] =
            enabledIds.map(\.uuidString) as CKRecordValue
        if let selectedId {
            record[CloudKitSchema.CameraSettingsKey.selectedId] =
                selectedId.uuidString as CKRecordValue
        } else {
            record[CloudKitSchema.CameraSettingsKey.selectedId] = nil
        }
        record[CloudKitSchema.CameraSettingsKey.modifiedAt] = modifiedAt as CKRecordValue
        return record
    }

    static func cameraSettingsEnabledIds(from record: CKRecord) -> [UUID] {
        let raw = (record[CloudKitSchema.CameraSettingsKey.enabledIds] as? [String]) ?? []
        return raw.compactMap(UUID.init(uuidString:))
    }

    static func cameraSettingsSelectedId(from record: CKRecord) -> UUID? {
        (record[CloudKitSchema.CameraSettingsKey.selectedId] as? String)
            .flatMap(UUID.init(uuidString:))
    }

    static func cameraSettingsOrientation(
        from record: CKRecord
    ) -> ExternalOutputOrientation? {
        guard let raw = record[CloudKitSchema.CameraSettingsKey.orientation] as? String
        else { return nil }
        return ExternalOutputOrientation.resolved(fromStored: raw)
    }

    /// Camera cutaway still JPEG record.
    static func makeCutawayRecord(
        id: UUID,
        createdAt: Date,
        existing: CKRecord? = nil,
        assetURL: URL? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.cutawayStill,
            recordID: CloudKitSchema.cutawayRecordID(for: id)
        )
        record[CloudKitSchema.CutawayKey.createdAt] = createdAt as CKRecordValue
        record[CloudKitSchema.CutawayKey.modifiedAt] = modifiedAt as CKRecordValue
        if let assetURL {
            record[CloudKitSchema.CutawayKey.asset] = CKAsset(fileURL: assetURL)
        }
        return record
    }

    static func cutawayAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.CutawayKey.asset] as? CKAsset)?.fileURL
    }

    static func cutawayCreatedAt(from record: CKRecord) -> Date {
        (record[CloudKitSchema.CutawayKey.createdAt] as? Date) ?? Date()
    }
}
