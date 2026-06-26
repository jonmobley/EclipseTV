// UnavailableLedger.swift
import Foundation
import os.log

/// A library entry whose backing file was purged by tvOS (Caches eviction). Kept so the
/// companion can show it as "unavailable" and offer to re-send it.
struct UnavailableItem: Codable, Equatable {
    let id: String        // file name (lastPathComponent), the stable cross-device id
    let name: String
    let isVideo: Bool
    let lastIndex: Int     // best-effort original position, used to restore in place
}

/// Persisted record of library items whose files have gone missing. These live only on
/// the TV's companion-facing manifest; the TV's own grid stays clean (the items are
/// removed from `MediaDataSource`). Not a singleton: `MediaDataSource` owns one built
/// with the same `UserDefaults` so tests stay isolated.
final class UnavailableLedger {

    private(set) var items: [UnavailableItem] = []

    private let storageKey = "EclipseTV.unavailableLedger"
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "UnavailableLedger")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Queries

    func contains(id: String) -> Bool {
        items.contains { $0.id == id }
    }

    func item(forId id: String) -> UnavailableItem? {
        items.first { $0.id == id }
    }

    // MARK: - Mutations

    /// Records (or updates) an unavailable item. Idempotent on `id`.
    func record(id: String, name: String, isVideo: Bool, lastIndex: Int) {
        let entry = UnavailableItem(id: id, name: name, isVideo: isVideo, lastIndex: lastIndex)
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = entry
        } else {
            items.append(entry)
        }
        save()
    }

    /// Removes the entry for `id`, returning it if present (e.g. on successful restore).
    @discardableResult
    func remove(id: String) -> UnavailableItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = items.remove(at: index)
        save()
        return removed
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UnavailableItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
