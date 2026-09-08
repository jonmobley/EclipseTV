//
//  CloudKitSharedZoneIndexTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CloudKitSharedZoneIndexTests {

    private func makeIndex(_ suite: String) throws -> CloudKitSharedZoneIndex {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CloudKitSharedZoneIndex(
            defaults: defaults,
            zonesKey: "\(suite).zones",
            showsKey: "\(suite).shows"
        )
    }

    private func makeRecord(
        type: String,
        name: String,
        owner: String
    ) -> CKRecord {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudKitSchema.zoneName, ownerName: owner
        )
        return CKRecord(
            recordType: type,
            recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
        )
    }

    /// The owner's zone is the only way to address a shared record again; rebuilding
    /// one from `CloudKitSchema` names our own zone and never resolves.
    @Test func learnsOwnerZoneForSharedRecord() throws {
        let index = try makeIndex("SharedZones.\(UUID().uuidString)")
        let record = makeRecord(
            type: CloudKitSchema.RecordType.mediaItem,
            name: "media-1",
            owner: "_ownerRecordName"
        )

        index.note(record)

        let resolved = index.recordID(forRecordName: "media-1")
        #expect(resolved?.zoneID.ownerName == "_ownerRecordName")
        #expect(resolved?.zoneID.zoneName == CloudKitSchema.zoneName)
        #expect(resolved?.recordName == "media-1")
    }

    @Test func unknownRecordHasNoSharedZone() throws {
        let index = try makeIndex("SharedZones.\(UUID().uuidString)")
        #expect(index.recordID(forRecordName: "missing") == nil)
    }

    /// A Show that arrived from someone else must not be re-uploaded, or the
    /// participant forks the owner's Show into their own private zone.
    @Test func sharedShowIsFlaggedAndPersists() throws {
        let suite = "SharedZones.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let index = CloudKitSharedZoneIndex(
            defaults: defaults,
            zonesKey: "\(suite).zones",
            showsKey: "\(suite).shows"
        )
        let showId = UUID()

        index.note(makeRecord(
            type: CloudKitSchema.RecordType.show,
            name: showId.uuidString,
            owner: "_owner"
        ))

        #expect(index.isSharedIn(showId: showId))

        let reloaded = CloudKitSharedZoneIndex(
            defaults: defaults,
            zonesKey: "\(suite).zones",
            showsKey: "\(suite).shows"
        )
        #expect(reloaded.isSharedIn(showId: showId))
    }

    @Test func nonShowRecordDoesNotFlagAShow() throws {
        let index = try makeIndex("SharedZones.\(UUID().uuidString)")
        let id = UUID()

        index.note(makeRecord(
            type: CloudKitSchema.RecordType.mediaItem,
            name: id.uuidString,
            owner: "_owner"
        ))

        #expect(index.isSharedIn(showId: id) == false)
    }

    @Test func removeAllForgetsSharesFromThePreviousAccount() throws {
        let index = try makeIndex("SharedZones.\(UUID().uuidString)")
        let showId = UUID()
        index.note(makeRecord(
            type: CloudKitSchema.RecordType.show,
            name: showId.uuidString,
            owner: "_owner"
        ))

        index.removeAll()

        #expect(index.isSharedIn(showId: showId) == false)
        #expect(index.recordID(forRecordName: showId.uuidString) == nil)
    }
}
