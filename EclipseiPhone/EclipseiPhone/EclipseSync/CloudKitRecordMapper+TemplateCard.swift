//
//  CloudKitRecordMapper+TemplateCard.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Maps a Show template card to and from its `TemplateCard`
//               iCloud record (contract shared with the Mac app).
//  Thread Safety: Pure functions - safe from any thread.
//

import CloudKit
import Foundation

// MARK: - TemplateCard

extension CloudKitRecordMapper {

    /// Builds a TemplateCard record. Sets `parent` only for share roots.
    ///
    /// - Parameters:
    ///   - card: The local card.
    ///   - existing: Cached server record to update (keeps its change tag).
    ///   - attachAsShareChild: Parent the record to its Show (shared Shows only).
    /// - Returns: The record, or nil when the config cannot be encoded.
    static func makeTemplateCardRecord(
        from card: ShowTemplateCard,
        existing: CKRecord? = nil,
        attachAsShareChild: Bool = false
    ) -> CKRecord? {
        guard let config = card.config.syncJSONString() else { return nil }
        typealias Key = CloudKitSchema.TemplateCardKey
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.templateCard,
            recordID: CloudKitSchema.templateCardRecordID(for: card.id)
        )
        record[Key.name] = card.name as CKRecordValue
        record[Key.template] = card.config.template.rawValue as CKRecordValue
        record[Key.config] = config as CKRecordValue
        record[Key.stackOrder] = Int64(card.stackOrder) as CKRecordValue
        record[Key.createdAt] = card.createdAt as CKRecordValue
        record[Key.modifiedAt] = card.modifiedAt as CKRecordValue
        applyShowLink(
            to: record,
            showId: card.showId,
            showIdKey: Key.showId,
            attachAsShareChild: attachAsShareChild
        )
        return record
    }

    /// Local card from a TemplateCard record.
    ///
    /// Lenient: an unknown template kind (a newer Mac) or a missing / bad
    /// config returns nil so the record is skipped rather than crashing.
    static func templateCard(from record: CKRecord) -> ShowTemplateCard? {
        typealias Key = CloudKitSchema.TemplateCardKey
        guard record.recordType == CloudKitSchema.RecordType.templateCard,
              let id = UUID(uuidString: record.recordID.recordName),
              let showRaw = record[Key.showId] as? String,
              let showId = UUID(uuidString: showRaw),
              let kindRaw = record[Key.template] as? String,
              OverlayCardTemplateKind(rawValue: kindRaw) != nil,
              let config = OverlayCardConfig.fromSyncJSON(record[Key.config] as? String)
        else { return nil }
        let createdAt = (record[Key.createdAt] as? Date) ?? Date()
        let name = (record[Key.name] as? String).flatMap(UserDisplayName.normalized)
        return ShowTemplateCard(
            id: id,
            showId: showId,
            name: name,
            config: config,
            stackOrder: cloudInt(record[Key.stackOrder]),
            createdAt: createdAt,
            modifiedAt: (record[Key.modifiedAt] as? Date) ?? createdAt
        )
    }

    private static func cloudInt(_ raw: Any?) -> Int {
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Int { return value }
        if let number = raw as? NSNumber { return number.intValue }
        return 0
    }
}

// MARK: - Engine Helper

extension CloudKitSyncEngine {

    /// TemplateCard record for a pending save, parented when its Show is shared.
    func makeTemplateCardRecordToSave(
        _ card: ShowTemplateCard,
        existing: CKRecord? = nil
    ) -> CKRecord? {
        let resolved = shareRoots.resolve(
            preferredShowId: card.showId,
            containingShowIds: [card.showId]
        )
        return CloudKitRecordMapper.makeTemplateCardRecord(
            from: card,
            existing: existing,
            attachAsShareChild: resolved.attachAsShareChild
        )
    }
}
