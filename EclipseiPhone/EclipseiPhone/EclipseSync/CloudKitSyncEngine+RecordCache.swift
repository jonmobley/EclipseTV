//
//  CloudKitSyncEngine+RecordCache.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Last-known CKRecord cache

extension CloudKitSyncEngine {

    /// Stores `record` so the next save of this id is an update, not an insert.
    func rememberLastKnown(_ record: CKRecord) {
        lastKnownRecords.remember(record)
    }

    /// Drops a cached record after a confirmed delete.
    func forgetLastKnown(_ recordID: CKRecord.ID) {
        lastKnownRecords.forget(recordID)
    }

    /// Server (or last saved) record for `recordID`, if one is cached.
    func existingRecord(for recordID: CKRecord.ID) -> CKRecord? {
        lastKnownRecords.record(for: recordID)
    }
}
