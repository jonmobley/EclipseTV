//
//  CloudKitRecordMapper+Prompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Prompter

extension CloudKitRecordMapper {

    /// Builds a Prompter record. Never sets `parent`: the script is private to the
    /// owner's devices even when its Show is shared.
    static func makePrompterRecord(
        from entry: PrompterScript,
        existing: CKRecord? = nil
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.prompter,
            recordID: CloudKitSchema.prompterRecordID(for: entry.showId)
        )
        record[CloudKitSchema.PrompterKey.showId] =
            entry.showId.uuidString as CKRecordValue
        record[CloudKitSchema.PrompterKey.script] = entry.script as CKRecordValue
        record[CloudKitSchema.PrompterKey.modifiedAt] = entry.modifiedAt as CKRecordValue
        record.parent = nil
        return record
    }

    /// Local script entry from a Prompter record.
    static func prompterScript(from record: CKRecord) -> PrompterScript? {
        guard record.recordType == CloudKitSchema.RecordType.prompter else { return nil }
        let fieldShowId = (record[CloudKitSchema.PrompterKey.showId] as? String)
            .flatMap(UUID.init(uuidString:))
        guard let showId = fieldShowId
            ?? CloudKitSchema.prompterShowId(fromRecordName: record.recordID.recordName)
        else { return nil }
        let script = record[CloudKitSchema.PrompterKey.script] as? String ?? ""
        let modifiedAt = (record[CloudKitSchema.PrompterKey.modifiedAt] as? Date)
            ?? record.modificationDate
            ?? .distantPast
        return PrompterScript(
            showId: showId,
            script: PrompterScriptStore.clamped(script),
            modifiedAt: modifiedAt
        )
    }
}
