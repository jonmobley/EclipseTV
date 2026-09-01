//
//  CloudKitRecordMapper+LivePoll.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - LivePoll

extension CloudKitRecordMapper {

    /// Builds a Live Poll card metadata record. Sets `parent` only for share roots.
    static func makeLivePollRecord(
        from item: ShowLivePoll,
        existing: CKRecord? = nil,
        modifiedAt: Date = Date(),
        attachAsShareChild: Bool = false
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.livePoll,
            recordID: CloudKitSchema.livePollRecordID(for: item.id)
        )
        record[CloudKitSchema.LivePollKey.pollId] = item.pollId as CKRecordValue
        record[CloudKitSchema.LivePollKey.title] = item.title as CKRecordValue
        record[CloudKitSchema.LivePollKey.questionCount] =
            item.questionCount as CKRecordValue
        record[CloudKitSchema.LivePollKey.createdAt] = item.createdAt as CKRecordValue
        record[CloudKitSchema.LivePollKey.modifiedAt] = modifiedAt as CKRecordValue
        applyShowLink(
            to: record,
            showId: item.showId,
            showIdKey: CloudKitSchema.LivePollKey.showId,
            attachAsShareChild: attachAsShareChild
        )
        return record
    }

    /// Local Live Poll card from a LivePoll record.
    static func livePoll(from record: CKRecord) -> ShowLivePoll? {
        guard record.recordType == CloudKitSchema.RecordType.livePoll,
              let uuid = UUID(uuidString: record.recordID.recordName),
              let pollId = record[CloudKitSchema.LivePollKey.pollId] as? String,
              let title = record[CloudKitSchema.LivePollKey.title] as? String,
              let showRaw = record[CloudKitSchema.LivePollKey.showId] as? String,
              let showId = UUID(uuidString: showRaw)
        else { return nil }
        let questionCount = (record[CloudKitSchema.LivePollKey.questionCount] as? Int)
            ?? 1
        let createdAt = (record[CloudKitSchema.LivePollKey.createdAt] as? Date)
            ?? Date()
        return ShowLivePoll(
            id: uuid,
            showId: showId,
            pollId: pollId,
            title: UserDisplayName.clamp(title),
            questionCount: max(questionCount, 1),
            createdAt: createdAt
        )
    }
}
