//
//  CloudKitRecordMapper+WebPage.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - WebPage

extension CloudKitRecordMapper {

    /// Builds a WebPage metadata record (no asset).
    static func makeWebPageRecord(
        from page: WebPage,
        existing: CKRecord? = nil,
        modifiedAt: Date = Date()
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.webPage,
            recordID: CloudKitSchema.webPageRecordID(for: page.id)
        )
        record[CloudKitSchema.WebPageKey.title] = page.title as CKRecordValue
        record[CloudKitSchema.WebPageKey.url] = page.url.absoluteString as CKRecordValue
        record[CloudKitSchema.WebPageKey.createdAt] = page.createdAt as CKRecordValue
        record[CloudKitSchema.WebPageKey.modifiedAt] = modifiedAt as CKRecordValue
        return record
    }

    /// Local page from a WebPage record.
    static func webPage(from record: CKRecord) -> WebPage? {
        guard record.recordType == CloudKitSchema.RecordType.webPage,
              let uuid = UUID(uuidString: record.recordID.recordName),
              let title = record[CloudKitSchema.WebPageKey.title] as? String,
              let urlString = record[CloudKitSchema.WebPageKey.url] as? String,
              let url = URL(string: urlString)
        else { return nil }
        let createdAt = (record[CloudKitSchema.WebPageKey.createdAt] as? Date) ?? Date()
        return WebPage(
            id: uuid,
            title: UserDisplayName.clamp(title),
            url: url,
            createdAt: createdAt
        )
    }
}
