//
//  ImportedMediaStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Durable registry of Photos imports that participate in CloudKit Sync.
///
/// Never folds into `CaptureStore` — that would strip Multipeer TV sendability.
@MainActor
final class ImportedMediaStore {

    static let shared = ImportedMediaStore()

    /// Posted when the import list or an item's sync state changes.
    static let didChangeNotification = Notification.Name("ImportedMediaStore.didChange")

    private(set) var records: [ImportedMediaRecord] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.imports.items"
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "ImportedMediaStore"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Reads

    /// Non-deleted imports, newest first.
    var allActive: [ImportedMediaRecord] {
        records.filter { !$0.isDeleted }.sorted { $0.capturedAt > $1.capturedAt }
    }

    /// Row whose CloudKit id or library filename matches `id`.
    func record(id: String) -> ImportedMediaRecord? {
        records.first {
            !$0.isDeleted && ($0.cloudId == id || $0.libraryId == id)
        }
    }

    /// CloudKit / library ids that must survive TV manifest prune.
    var keepIds: Set<String> {
        Set(records.filter { !$0.isDeleted }.flatMap { [$0.cloudId, $0.libraryId] })
    }

    /// Imports CloudKit should enqueue.
    var idsNeedingUpload: [String] {
        records
            .filter { !$0.isDeleted && $0.syncState == .pendingUpload }
            .map(\.cloudId)
    }

    // MARK: - Mutations

    /// Registers a local import for CloudKit upload.
    @discardableResult
    func register(
        libraryId: String,
        isVideo: Bool,
        duration: Double,
        orientation: ExternalOutputOrientation,
        showId: UUID?
    ) -> ImportedMediaRecord {
        if let existing = record(id: libraryId) { return existing }
        let ext = (libraryId as NSString).pathExtension
        let record = ImportedMediaRecord(
            libraryId: libraryId,
            isVideo: isVideo,
            duration: duration,
            orientation: orientation,
            showId: showId,
            fileExtension: ext.isEmpty ? (isVideo ? "mov" : "jpg") : ext,
            syncState: .pendingUpload
        )
        records.append(record)
        persist()
        scheduleSaveIfNeeded(cloudId: record.cloudId)
        return record
    }

    /// Inserts or replaces a row and posts change.
    func upsert(_ record: ImportedMediaRecord) {
        if let index = records.firstIndex(where: { $0.cloudId == record.cloudId }) {
            records[index] = record
        } else {
            records.append(record)
        }
        persist()
    }

    /// Applies a remote import without scheduling an upload.
    func applyRemote(_ remote: ImportedMediaRecord) {
        if let index = records.firstIndex(where: { $0.cloudId == remote.cloudId }) {
            let local = records[index]
            var merged = remote
            if local.syncState != .remoteOnly {
                merged.syncState = local.syncState == .downloading
                    ? .downloading
                    : (local.syncState == .pendingUpload ? .pendingUpload : .synced)
            }
            records[index] = merged
        } else {
            records.append(remote)
        }
        persist()
    }

    /// Marks sync state for `cloudId`.
    func setSyncState(id cloudId: String, _ state: CaptureSyncState) {
        guard let index = records.firstIndex(where: { $0.cloudId == cloudId }) else {
            return
        }
        records[index].syncState = state
        persist()
    }

    /// Soft-deletes locally and schedules a cloud delete.
    func markDeleted(cloudId: String) {
        guard let index = records.firstIndex(where: { $0.cloudId == cloudId }) else {
            return
        }
        records[index].isDeleted = true
        persist()
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleMediaDelete(cloudId: cloudId)
    }

    /// Removes the row after the cloud delete is acknowledged.
    func purge(id cloudId: String) {
        let before = records.count
        records.removeAll { $0.cloudId == cloudId }
        guard records.count != before else { return }
        persist()
    }

    /// Clears local bytes only; keeps the registry entry as `remoteOnly`.
    func removeLocalDownload(id cloudId: String) {
        guard let index = records.firstIndex(where: { $0.cloudId == cloudId }) else {
            return
        }
        let libraryId = records[index].libraryId
        let mode = records[index].orientation.libraryMode
        LocalMediaStore.shared.remove(
            id: libraryId, mode: mode, provenance: .imported
        )
        records[index].syncState = .remoteOnly
        persist()
    }

    private func scheduleSaveIfNeeded(cloudId: String) {
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleMediaSave(cloudId: cloudId)
    }

    // MARK: - Persistence

    private func load() {
        records = SalvagingListDecoder.decodeList(
            ImportedMediaRecord.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(records)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode imports: \(error.localizedDescription)")
        }
    }
}
