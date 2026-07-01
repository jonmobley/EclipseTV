//
//  PendingUploadStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PendingUploadStore.swift
import Foundation
import os.log

/// A persistent queue of media the user added on the phone that still needs to be pushed
/// to an Apple TV.
///
/// The companion is normally a remote for the TV library, but the user can also add
/// photos and videos while no Apple TV is connected. Those additions are shown
/// immediately in the grid (see `TVLibraryStore.addLocalItem`), their full-resolution
/// files are kept in `LocalMediaStore`, and their metadata is recorded here so they can
/// be uploaded automatically the next time a TV connects.
///
/// Entries are keyed by the same id `TVLibraryStore`/`LocalMediaStore` use (the resource
/// name the phone sends, i.e. the file's `lastPathComponent`). Once the TV confirms an
/// item by including it in a fresh manifest, it is removed from this queue.
@MainActor
final class PendingUploadStore {

    /// Shared instance used by the add flow, the library store, and the connection manager.
    static let shared = PendingUploadStore()

    /// A single queued upload: the library entry to display plus enough to re-send it.
    struct PendingUpload: Codable, Equatable {
        let item: LibraryItemDTO
    }

    private(set) var uploads: [PendingUpload] = []

    private let defaultsKey = "EclipseTV.companion.pendingUploads"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "PendingUploadStore")

    private init() {
        load()
    }

    // MARK: - Reads

    /// The library entries for every queued upload, in the order they were added.
    var items: [LibraryItemDTO] { uploads.map { $0.item } }

    /// The set of ids currently awaiting upload. Used to protect their local files and
    /// thumbnails from pruning while they haven't yet been confirmed by a TV.
    var pendingIds: Set<String> { Set(uploads.map { $0.item.id }) }

    var isEmpty: Bool { uploads.isEmpty }

    func contains(id: String) -> Bool {
        uploads.contains { $0.item.id == id }
    }

    // MARK: - Writes

    /// Adds an item to the queue (no-op if already queued).
    func enqueue(_ item: LibraryItemDTO) {
        guard !contains(id: item.id) else { return }
        uploads.append(PendingUpload(item: item))
        persist()
    }

    /// Removes an item from the queue, e.g. after the TV confirms it or the user deletes
    /// it before it ever synced.
    func remove(id: String) {
        let before = uploads.count
        uploads.removeAll { $0.item.id == id }
        if uploads.count != before { persist() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PendingUpload].self, from: data) else {
            return
        }
        uploads = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(uploads) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } else {
            logger.error("Failed to encode pending uploads for persistence")
        }
    }
}
