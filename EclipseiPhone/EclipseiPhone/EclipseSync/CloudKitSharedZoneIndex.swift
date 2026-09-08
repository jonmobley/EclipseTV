//
//  CloudKitSharedZoneIndex.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// Remembers which zone each record accepted through a `CKShare` actually lives in.
///
/// `CloudKitSchema.zoneID` is pinned to `CKCurrentUserDefaultName`, which is correct
/// for the private database and meaningless in the shared one: a shared zone is owned
/// by the *sharer*, so its zone ID carries their user record name. Rebuilding a record
/// ID from the schema therefore never resolves against the shared database, which is
/// why participants could see shared tiles but never download their media.
///
/// The index also names the Shows that arrived from someone else, so the private
/// engine can leave them alone instead of forking them into the user's own zone.
@MainActor
final class CloudKitSharedZoneIndex {

    private var zones: [String: [String]] = [:]
    private var sharedShowIds: Set<String> = []
    private let defaults: UserDefaults
    private let zonesKey: String
    private let showsKey: String

    init(
        defaults: UserDefaults = .standard,
        zonesKey: String = "EclipseTV.cloudKit.sharedRecordZones",
        showsKey: String = "EclipseTV.cloudKit.sharedShowIds"
    ) {
        self.defaults = defaults
        self.zonesKey = zonesKey
        self.showsKey = showsKey
        zones = (defaults.dictionary(forKey: zonesKey) as? [String: [String]]) ?? [:]
        sharedShowIds = Set(defaults.stringArray(forKey: showsKey) ?? [])
    }

    // MARK: - Learning

    /// Records the owning zone of a record fetched from the shared database.
    func note(_ record: CKRecord) {
        let zoneID = record.recordID.zoneID
        zones[record.recordID.recordName] = [zoneID.zoneName, zoneID.ownerName]
        if record.recordType == CloudKitSchema.RecordType.show {
            sharedShowIds.insert(record.recordID.recordName)
        }
        persist()
    }

    // MARK: - Reads

    /// Zone the shared copy of `recordName` lives in, if it is known.
    func zoneID(forRecordName recordName: String) -> CKRecordZone.ID? {
        guard let parts = zones[recordName], parts.count == 2 else { return nil }
        return CKRecordZone.ID(zoneName: parts[0], ownerName: parts[1])
    }

    /// Record ID addressing the shared copy of `recordName`.
    func recordID(forRecordName recordName: String) -> CKRecord.ID? {
        guard let zoneID = zoneID(forRecordName: recordName) else { return nil }
        return CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Whether this Show belongs to another iCloud user and must not be re-uploaded.
    func isSharedIn(showId: UUID) -> Bool {
        sharedShowIds.contains(showId.uuidString)
    }

    /// Drops every entry (account switch — shares belong to the old account).
    func removeAll() {
        zones.removeAll()
        sharedShowIds.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(zones, forKey: zonesKey)
        defaults.set(Array(sharedShowIds), forKey: showsKey)
    }
}
