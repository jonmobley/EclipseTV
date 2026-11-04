//
//  PrompterSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct PrompterSyncMappingTests {

    @Test func recordNameIsPrefixedShowId() {
        let showId = UUID()
        let recordID = CloudKitSchema.prompterRecordID(for: showId)
        #expect(recordID.recordName == "prompter-" + showId.uuidString)
        #expect(recordID.zoneID == CloudKitSchema.zoneID)
        #expect(CloudKitSchema.prompterShowId(fromRecordName: recordID.recordName) == showId)
    }

    @Test func prompterShowIdParsesPrefixedNamesOnly() {
        #expect(CloudKitSchema.prompterShowId(fromRecordName: UUID().uuidString) == nil)
        #expect(CloudKitSchema.prompterShowId(fromRecordName: "prompter-nope") == nil)
        #expect(CloudKitSchema.prompterShowId(fromRecordName: "eclipse.background") == nil)
    }

    @Test func recordRoundTripsScriptShowIdAndClock() throws {
        let entry = PrompterScript(
            showId: UUID(),
            script: "Welcome, everyone.\n\nTonight we…",
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = CloudKitRecordMapper.makePrompterRecord(from: entry)
        #expect(record.recordType == CloudKitSchema.RecordType.prompter)
        #expect(record.recordID.recordName == CloudKitSchema.prompterRecordName(for: entry.showId))

        let decoded = try #require(CloudKitRecordMapper.prompterScript(from: record))
        #expect(decoded == entry)
    }

    @Test func emptyScriptRoundTripsAsEmpty() throws {
        let entry = PrompterScript(showId: UUID(), script: "", modifiedAt: Date())
        let record = CloudKitRecordMapper.makePrompterRecord(from: entry)
        #expect(record[CloudKitSchema.PrompterKey.script] as? String == "")
        let decoded = try #require(CloudKitRecordMapper.prompterScript(from: record))
        #expect(decoded.script == "")
    }

    @Test func recordNeverHasAParentEvenWhenReused() {
        let showId = UUID()
        let existing = CKRecord(
            recordType: CloudKitSchema.RecordType.prompter,
            recordID: CloudKitSchema.prompterRecordID(for: showId)
        )
        existing.parent = CKRecord.Reference(
            recordID: CloudKitSchema.showRecordID(for: showId), action: .none
        )
        let entry = PrompterScript(showId: showId, script: "Private", modifiedAt: Date())
        let record = CloudKitRecordMapper.makePrompterRecord(from: entry, existing: existing)
        #expect(record.parent == nil)
        #expect(CloudKitRecordMapper.isPrivateToMe(record))
    }

    @Test func showIdFallsBackToRecordName() throws {
        let showId = UUID()
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.prompter,
            recordID: CloudKitSchema.prompterRecordID(for: showId)
        )
        record[CloudKitSchema.PrompterKey.script] = "No showId field" as CKRecordValue
        let decoded = try #require(CloudKitRecordMapper.prompterScript(from: record))
        #expect(decoded.showId == showId)
        #expect(decoded.script == "No showId field")
    }

    @Test func parentedRecordIsNotPrivateToMe() {
        let showId = UUID()
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.prompter,
            recordID: CloudKitSchema.prompterRecordID(for: showId)
        )
        record.parent = CKRecord.Reference(
            recordID: CloudKitSchema.showRecordID(for: showId), action: .none
        )
        #expect(!CloudKitRecordMapper.isPrivateToMe(record))
    }

    @Test func otherRecordTypesAreRejected() {
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.countdown,
            recordID: CloudKitSchema.prompterRecordID(for: UUID())
        )
        #expect(CloudKitRecordMapper.prompterScript(from: record) == nil)
    }
}
