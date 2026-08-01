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
/// Entries are tagged with a `libraryMode` so Landscape and Vertical libraries flush
/// independently. Legacy untagged entries migrate to landscape.
@MainActor
final class PendingUploadStore {

    /// Shared instance used by the add flow, the library store, and the connection manager.
    static let shared = PendingUploadStore()

    /// A single queued upload: the library entry to display plus enough to re-send it.
    struct PendingUpload: Codable, Equatable {
        let item: LibraryItemDTO
        /// `"landscape"` / `"vertical"`; nil means legacy (treated as landscape).
        var libraryMode: String?
    }

    private(set) var uploads: [PendingUpload] = []

    private let defaultsKey = "EclipseTV.companion.pendingUploads"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "PendingUploadStore")

    private init() {
        load()
    }

    // MARK: - Reads

    /// All queued uploads (both modes). Prefer `uploads(for:)` for mode-scoped work.
    var allUploads: [PendingUpload] { uploads }

    /// Queued uploads for a library mode (legacy nil → landscape).
    func uploads(for mode: EclipseShareProtocol.LibraryMode) -> [PendingUpload] {
        uploads.filter { EclipseShareProtocol.LibraryMode.resolved(from: $0.libraryMode) == mode }
    }

    /// Library entries for the given mode, in queue order.
    func items(for mode: EclipseShareProtocol.LibraryMode) -> [LibraryItemDTO] {
        uploads(for: mode).map(\.item)
    }

    /// Ids awaiting upload in the given mode.
    func pendingIds(for mode: EclipseShareProtocol.LibraryMode) -> Set<String> {
        Set(uploads(for: mode).map { $0.item.id })
    }

    /// Convenience for the active display mode.
    var items: [LibraryItemDTO] {
        items(for: ExternalOutputSettings.libraryMode)
    }

    var pendingIds: Set<String> {
        pendingIds(for: ExternalOutputSettings.libraryMode)
    }

    var isEmpty: Bool { uploads.isEmpty }

    func contains(id: String,
                  mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) -> Bool {
        uploads(for: mode).contains { $0.item.id == id }
    }

    // MARK: - Writes

    /// Adds an item to the queue for `mode` (no-op if already queued in that mode).
    func enqueue(_ item: LibraryItemDTO,
                 mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) {
        guard !contains(id: item.id, mode: mode) else { return }
        uploads.append(PendingUpload(item: item, libraryMode: mode.rawValue))
        persist()
    }

    /// Removes an item from the queue for `mode`.
    func remove(id: String,
                mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) {
        let before = uploads.count
        uploads.removeAll {
            $0.item.id == id
                && EclipseShareProtocol.LibraryMode.resolved(from: $0.libraryMode) == mode
        }
        if uploads.count != before { persist() }
    }

    /// Replaces a queued item’s DTO (e.g. after loop / mute changes) when still pending.
    func update(_ item: LibraryItemDTO,
                mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) {
        guard let index = uploads.firstIndex(where: {
            $0.item.id == item.id
                && EclipseShareProtocol.LibraryMode.resolved(from: $0.libraryMode) == mode
        }) else { return }
        uploads[index] = PendingUpload(item: item, libraryMode: mode.rawValue)
        persist()
    }

    /// Clears the in-memory queue and persisted UserDefaults entry. Intended for unit tests.
    func removeAll() {
        guard !uploads.isEmpty || UserDefaults.standard.data(forKey: defaultsKey) != nil else { return }
        uploads = []
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PendingUpload].self, from: data) else {
            return
        }
        // Migrate legacy untagged entries → landscape.
        var migrated = false
        uploads = decoded.map { entry in
            guard entry.libraryMode == nil else { return entry }
            migrated = true
            var copy = entry
            copy.libraryMode = EclipseShareProtocol.LibraryMode.landscape.rawValue
            return copy
        }
        if migrated { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(uploads) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } else {
            logger.error("Failed to encode pending uploads for persistence")
        }
    }
}
