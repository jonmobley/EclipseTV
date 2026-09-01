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
        lastKnownRecords[record.recordID] = record
    }

    /// Drops a cached record after a confirmed delete.
    func forgetLastKnown(_ recordID: CKRecord.ID) {
        lastKnownRecords[recordID] = nil
    }

    /// Server (or last saved) record for `recordID`, if this session has seen it.
    func existingRecord(for recordID: CKRecord.ID) -> CKRecord? {
        lastKnownRecords[recordID]
    }
}
