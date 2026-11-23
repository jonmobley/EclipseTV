//
//  MusicSyncLedger.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// iCloud bookkeeping for songs or playlists: each item's last-writer-wins clock
/// and whether the server has acknowledged its latest save.
///
/// Kept beside the stores rather than inside `AudioTrack` / `AudioPlaylist` so the
/// saved library format does not change. One ledger per store, keyed by a prefix.
///
/// Thread safety: main actor only, like the stores that own it.
@MainActor
final class MusicSyncLedger {

    private let defaults: UserDefaults
    private let clocksKey: String
    private let syncedKey: String
    private var clocks: [String: Date]
    private var synced: Set<String>

    /// Creates a ledger stored in `defaults` under `keyPrefix`.
    /// - Parameters:
    ///   - defaults: Where the ledger is saved.
    ///   - keyPrefix: Distinguishes the song ledger from the playlist ledger.
    init(defaults: UserDefaults, keyPrefix: String) {
        self.defaults = defaults
        clocksKey = keyPrefix + ".modifiedAt"
        syncedKey = keyPrefix + ".syncedIds"
        clocks = defaults.dictionary(forKey: clocksKey) as? [String: Date] ?? [:]
        synced = Set(defaults.stringArray(forKey: syncedKey) ?? [])
    }

    // MARK: - Queries

    /// The item's clock, or nil when it was never edited or received.
    func modifiedAt(_ id: UUID) -> Date? {
        clocks[id.uuidString]
    }

    /// Whether the server has acknowledged the item's latest save.
    func isSynced(_ id: UUID) -> Bool {
        synced.contains(id.uuidString)
    }

    // MARK: - Updates

    /// Records a local edit: new clock, not yet acknowledged.
    func stamp(_ id: UUID, at date: Date) {
        clocks[id.uuidString] = date
        synced.remove(id.uuidString)
        save()
    }

    /// Records a remote copy that was applied: its clock, already on the server.
    func acceptRemote(_ id: UUID, modifiedAt: Date) {
        clocks[id.uuidString] = modifiedAt
        synced.insert(id.uuidString)
        save()
    }

    /// Records that the server accepted the item's save.
    func markSynced(_ id: UUID) {
        guard synced.insert(id.uuidString).inserted else { return }
        save()
    }

    /// Drops everything known about a deleted item.
    func forget(_ id: UUID) {
        let hadClock = clocks.removeValue(forKey: id.uuidString) != nil
        let wasSynced = synced.remove(id.uuidString) != nil
        if hadClock || wasSynced { save() }
    }

    /// Forgets every acknowledgement (zone loss, iCloud account switch).
    func markAllNeedsUpload() {
        guard !synced.isEmpty else { return }
        synced.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(clocks, forKey: clocksKey)
        defaults.set(Array(synced), forKey: syncedKey)
    }
}
