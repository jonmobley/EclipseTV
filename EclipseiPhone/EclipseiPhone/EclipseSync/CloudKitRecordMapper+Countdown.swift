//
//  CloudKitRecordMapper+Countdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Countdown

extension CloudKitRecordMapper {

    /// Builds a Countdown metadata record. Sets `parent` only for share roots.
    static func makeCountdownRecord(
        from item: ShowCountdown,
        existing: CKRecord? = nil,
        modifiedAt: Date = Date(),
        attachAsShareChild: Bool = false
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.countdown,
            recordID: CloudKitSchema.countdownRecordID(for: item.id)
        )
        record[CloudKitSchema.CountdownKey.name] = item.name as CKRecordValue
        record[CloudKitSchema.CountdownKey.duration] = item.duration as CKRecordValue
        record[CloudKitSchema.CountdownKey.createdAt] = item.createdAt as CKRecordValue
        record[CloudKitSchema.CountdownKey.modifiedAt] = modifiedAt as CKRecordValue
        applyShowLink(
            to: record,
            showId: item.showId,
            showIdKey: CloudKitSchema.CountdownKey.showId,
            attachAsShareChild: attachAsShareChild
        )
        return record
    }

    /// Local countdown from a Countdown record.
    static func countdown(from record: CKRecord) -> ShowCountdown? {
        guard record.recordType == CloudKitSchema.RecordType.countdown,
              let uuid = UUID(uuidString: record.recordID.recordName),
              let name = record[CloudKitSchema.CountdownKey.name] as? String,
              let showRaw = record[CloudKitSchema.CountdownKey.showId] as? String,
              let showId = UUID(uuidString: showRaw)
        else { return nil }
        let duration = (record[CloudKitSchema.CountdownKey.duration] as? Int)
            ?? CountdownController.defaultDuration
        let createdAt = (record[CloudKitSchema.CountdownKey.createdAt] as? Date)
            ?? Date()
        return ShowCountdown(
            id: uuid,
            showId: showId,
            name: UserDisplayName.clamp(name),
            duration: CountdownController.clampedDuration(duration),
            createdAt: createdAt
        )
    }
}
