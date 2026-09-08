//
//  CloudKitRecordSystemFieldsStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import os.log

/// Durable cache of CloudKit *system* fields (record id, type, change tag).
///
/// A save built from a bare `CKRecord` is an insert, so CloudKit rejects it once
/// the id exists on the server. The recovery path for that rejection applies the
/// server copy as the conflict winner, which silently reverts local-only edits
/// (Fit mode, framing, loop, mute). Keeping the change tag across launches makes
/// the first save of each session an update, so the collision never happens.
///
/// Only system fields are stored — never user field values or assets — so the
/// file stays small regardless of library size.
@MainActor
final class CloudKitRecordSystemFieldsStore {

    private var records: [CKRecord.ID: CKRecord] = [:]
    private let fileURL: URL
    private var needsFlush = false
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CloudKitRecordCache"
    )

    init(fileName: String = "recordSystemFields.plist") {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let directory = base.appendingPathComponent("EclipseSync", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent(fileName)
        load()
    }

    // MARK: - Access

    /// Last known server record for `recordID`, if one was cached.
    func record(for recordID: CKRecord.ID) -> CKRecord? {
        records[recordID]
    }

    /// Caches `record`'s system fields so the next save of this id is an update.
    func remember(_ record: CKRecord) {
        records[record.recordID] = record
        scheduleFlush()
    }

    /// Drops a cached record after a confirmed delete.
    func forget(_ recordID: CKRecord.ID) {
        guard records.removeValue(forKey: recordID) != nil else { return }
        scheduleFlush()
    }

    /// Clears every entry (zone loss, account switch).
    func removeAll() {
        records.removeAll()
        needsFlush = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    /// Coalesces writes so a bulk remote apply flushes once, not per record.
    private func scheduleFlush() {
        guard !needsFlush else { return }
        needsFlush = true
        Task { @MainActor [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        guard needsFlush else { return }
        needsFlush = false
        var encoded: [String: Data] = [:]
        for (recordID, record) in records {
            let archiver = NSKeyedArchiver(requiringSecureCoding: true)
            record.encodeSystemFields(with: archiver)
            archiver.finishEncoding()
            encoded[Self.key(for: recordID)] = archiver.encodedData
        }
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: encoded, format: .binary, options: 0
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Record cache write failed: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let raw = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Data] else {
            logger.error("Record cache unreadable; starting empty")
            return
        }
        for value in raw.values {
            guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: value) else {
                continue
            }
            unarchiver.requiresSecureCoding = true
            if let record = CKRecord(coder: unarchiver) {
                records[record.recordID] = record
            }
            unarchiver.finishDecoding()
        }
    }

    private static func key(for recordID: CKRecord.ID) -> String {
        [
            recordID.zoneID.ownerName,
            recordID.zoneID.zoneName,
            recordID.recordName
        ].joined(separator: "|")
    }
}
