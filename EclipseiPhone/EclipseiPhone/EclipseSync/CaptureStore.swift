//
//  CaptureStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Durable phone-owned registry of in-app captures (and CloudKit-fetched captures).
///
/// Never touched by Apple TV manifest sync. Files live in `Captures/<Mode>/` via
/// `LocalMediaStore` with `.captured` provenance.
@MainActor
final class CaptureStore {

    static let shared = CaptureStore()

    /// Posted when the capture list or an item's sync state changes.
    static let didChangeNotification = Notification.Name("CaptureStore.didChange")

    private(set) var records: [CaptureRecord] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.captures.items"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "CaptureStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Reads

    /// Non-deleted captures for the active Display Mode, newest first.
    var capturesForCurrentMode: [CaptureRecord] {
        let mode = ExternalOutputSettings.orientation
        return records
            .filter { !$0.isDeleted && $0.orientation == mode }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// All non-deleted captures across modes, newest first.
    var allActive: [CaptureRecord] {
        records.filter { !$0.isDeleted }.sorted { $0.capturedAt > $1.capturedAt }
    }

    /// Capture whose library file name or UUID matches `id`.
    func record(id: String) -> CaptureRecord? {
        records.first {
            !$0.isDeleted && ($0.id == id || $0.libraryFileName == id)
        }
    }

    /// Whether `id` is a capture (not an imported library item).
    func contains(id: String) -> Bool {
        record(id: id) != nil
    }

    /// Capture UUID / library ids that must survive TV manifest prune.
    var keepIds: Set<String> {
        Set(records.filter { !$0.isDeleted }.flatMap { [$0.id, $0.libraryFileName] })
    }

    /// Captures the CloudKit engine should enqueue — never `.localOnly`.
    ///
    /// Phone-owned captures stay off iCloud until sync is deliberately turned on for
    /// them. Bootstrap must not treat every on-disk capture as pending upload.
    var idsNeedingUpload: [String] {
        records
            .filter { !$0.isDeleted && $0.syncState != .localOnly }
            .map(\.id)
    }

    // MARK: - Mutations

    /// Inserts or replaces a capture and posts change.
    func upsert(_ record: CaptureRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        persist()
        if !EclipseSyncController.shared.isApplyingRemote {
            EclipseSyncController.shared.backend.scheduleCaptureSave(id: record.id)
        }
    }

    /// Copies a fresh capture into `LocalMediaStore` and registers it once it has landed.
    ///
    /// The record is created only after the copy succeeds. Publishing it first shows a
    /// tile with nothing behind it, and it is also what would upload a metadata-only
    /// CloudKit record — marked Synced here, undownloadable everywhere else.
    ///
    /// Captures stay `.localOnly`: cloud sync for captures is deliberately not scheduled
    /// yet. Turning it on means calling `scheduleCaptureSave` from this completion.
    func addLocalCapture(
        fileURL: URL,
        isVideo: Bool,
        duration: Double,
        showId: UUID?,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation,
        completion: ((CaptureRecord?) -> Void)? = nil
    ) {
        let ext = fileURL.pathExtension.lowercased()
        let safeExt = ext.isEmpty ? (isVideo ? "mov" : "jpg") : ext
        let record = CaptureRecord(
            id: UUID().uuidString,
            isVideo: isVideo,
            duration: duration,
            orientation: orientation,
            showId: showId,
            fileExtension: safeExt,
            syncState: .localOnly
        )
        LocalMediaStore.shared.store(
            fileURL: fileURL,
            forId: record.libraryFileName,
            mode: orientation.libraryMode,
            provenance: .captured
        ) { [weak self] stored in
            guard let self else {
                completion?(nil)
                return
            }
            guard stored else {
                self.logger.error("Capture copy failed; not registering \(record.id, privacy: .public)")
                completion?(nil)
                return
            }
            self.register(record)
            completion?(record)
        }
    }

    /// Inserts a landed capture, adds it to its Show, and refreshes the merged grid.
    private func register(_ record: CaptureRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        persist()
        if let showId = record.showId {
            LocalAlbumStore.shared.add(itemId: record.libraryFileName, toAlbumId: showId)
        }
        // Captures reach the grids as library DTOs merged into the TV mirror.
        TVLibraryStore.shared.refreshMergedCaptures()
    }

    /// Applies a remote (CloudKit) capture without scheduling an upload.
    func applyRemote(_ record: CaptureRecord) {
        var copy = record
        if LocalMediaStore.shared.hasMedia(
            forId: copy.libraryFileName,
            mode: copy.orientation.libraryMode
        ) {
            copy.syncState = .synced
        } else if copy.syncState != .downloading {
            copy.syncState = .remoteOnly
        }
        if let index = records.firstIndex(where: { $0.id == copy.id }) {
            let local = records[index]
            records[index] = CloudKitConflictResolver.mergeCaptures(
                local: local,
                remote: copy,
                preferRemote: true
            )
        } else {
            records.insert(copy, at: 0)
        }
        persist()
    }

    /// Updates sync state for an existing capture.
    func setSyncState(id: String, _ state: CaptureSyncState) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard records[index].syncState != state else { return }
        records[index].syncState = state
        persist()
    }

    /// Soft-deletes locally and schedules a cloud delete.
    func delete(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        LocalMediaStore.shared.remove(
            id: record.libraryFileName,
            mode: record.orientation.libraryMode,
            provenance: .captured
        )
        LocalAlbumStore.shared.removeItemFromAllAlbums(itemId: record.libraryFileName)
        records[index].isDeleted = true
        persist()
        EclipseSyncController.shared.backend.scheduleCaptureDelete(id: id)
    }

    /// Hard-removes a record after the cloud delete acknowledges (or for remote tombstones).
    func purge(id: String) {
        let before = records.count
        if let record = records.first(where: { $0.id == id }) {
            LocalMediaStore.shared.remove(
                id: record.libraryFileName,
                mode: record.orientation.libraryMode,
                provenance: .captured
            )
            LocalAlbumStore.shared.removeItemFromAllAlbums(itemId: record.libraryFileName)
        }
        records.removeAll { $0.id == id }
        guard records.count != before else { return }
        persist()
    }

    /// Removes only the local bytes; keeps the registry entry as `remoteOnly`.
    func removeLocalDownload(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        LocalMediaStore.shared.remove(
            id: record.libraryFileName,
            mode: record.orientation.libraryMode,
            provenance: .captured
        )
        records[index].syncState = .remoteOnly
        persist()
    }

    // MARK: - Persistence

    private func load() {
        records = SalvagingListDecoder.decodeList(
            CaptureRecord.self,
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
            logger.error("Failed to encode captures: \(error.localizedDescription)")
        }
    }
}
