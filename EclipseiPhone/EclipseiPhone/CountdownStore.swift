//
//  CountdownStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists per-Show countdown tiles as JSON metadata in UserDefaults.
@MainActor
final class CountdownStore {

    static let shared = CountdownStore()

    /// Posted when countdowns change.
    static let didChangeNotification = Notification.Name("CountdownStore.didChange")

    enum StoreError: LocalizedError {
        case emptyName

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter a name for the Countdown."
            }
        }
    }

    private(set) var countdowns: [ShowCountdown] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.countdowns.items"
    private let syncedIdsKey = "EclipseTV.countdowns.syncedIds"
    private var syncedIds: Set<String> = []
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CountdownStore"
    )

    private var didMigrateLegacy = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Queries

    /// Countdowns belonging to `showId`, oldest first (surface append order).
    func countdowns(forShowId showId: UUID) -> [ShowCountdown] {
        countdowns.filter { $0.showId == showId }
    }

    /// Countdown with `id`, if any.
    func countdown(id: UUID) -> ShowCountdown? {
        countdowns.first { $0.id == id }
    }

    /// Next default name in `showId` (`Countdown`, then `Countdown 2`, …).
    func nextDefaultName(inShowId showId: UUID) -> String {
        let names = Set(countdowns(forShowId: showId).map(\.name))
        if !names.contains("Countdown") { return "Countdown" }
        var n = 2
        while names.contains("Countdown \(n)") { n += 1 }
        return "Countdown \(n)"
    }

    // MARK: - Mutations

    /// Creates a countdown and appends it at the end of this Show's surface.
    @discardableResult
    func create(
        name: String,
        showId: UUID,
        duration: Int
    ) throws -> ShowCountdown {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        let item = ShowCountdown(
            showId: showId,
            name: trimmed,
            duration: CountdownController.clampedDuration(duration)
        )
        countdowns.append(item)
        persist()
        LocalAlbumStore.shared.addCountdown(item.id, toAlbumId: showId)
        scheduleSaveIfNeeded(id: item.id)
        return item
    }

    /// Renames the countdown with `id` when present.
    func rename(id: UUID, to name: String) throws {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard let index = countdowns.firstIndex(where: { $0.id == id }) else { return }
        countdowns[index].name = trimmed
        persist()
        scheduleSaveIfNeeded(id: id)
    }

    /// Sets the length of the countdown with `id`.
    func setDuration(id: UUID, seconds: Int) {
        guard let index = countdowns.firstIndex(where: { $0.id == id }) else { return }
        let next = CountdownController.clampedDuration(seconds)
        guard countdowns[index].duration != next else { return }
        countdowns[index].duration = next
        persist()
        scheduleSaveIfNeeded(id: id)
    }

    /// Deletes the countdown with `id` when present.
    func delete(id: UUID) {
        guard let item = countdowns.first(where: { $0.id == id }) else { return }
        countdowns.removeAll { $0.id == id }
        syncedIds.remove(id.uuidString)
        persist()
        LocalAlbumStore.shared.removeCountdown(id, fromAlbumId: item.showId)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleCountdownDelete(id: id)
    }

    /// Purges after a CloudKit tombstone without echoing a delete.
    func purgeRemote(id: UUID) {
        guard countdowns.contains(where: { $0.id == id }) else { return }
        countdowns.removeAll { $0.id == id }
        syncedIds.remove(id.uuidString)
        persist()
    }

    /// Inserts or replaces a countdown that arrived from iCloud.
    func applyRemote(_ item: ShowCountdown) {
        if let index = countdowns.firstIndex(where: { $0.id == item.id }) {
            countdowns[index] = item
        } else {
            countdowns.append(item)
        }
        syncedIds.insert(item.id.uuidString)
        persist()
    }

    /// Records that the backend accepted this countdown's upload.
    func markSynced(id: UUID) {
        guard !syncedIds.contains(id.uuidString) else { return }
        syncedIds.insert(id.uuidString)
        defaults.set(Array(syncedIds), forKey: syncedIdsKey)
    }

    /// Countdowns the server has not acknowledged yet.
    var idsNeedingUpload: [UUID] {
        countdowns.filter { !syncedIds.contains($0.id.uuidString) }.map(\.id)
    }

    /// Deletes every countdown belonging to `showId`.
    func deleteAll(forShowId showId: UUID) {
        let before = countdowns.count
        countdowns.removeAll { $0.showId == showId }
        guard countdowns.count != before else { return }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        syncedIds = Set(defaults.stringArray(forKey: syncedIdsKey) ?? [])
        countdowns = SalvagingListDecoder.decodeList(
            ShowCountdown.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    /// Turns the retired singleton tool into a real countdown (shared store only).
    func migrateLegacyToolTokensIfNeeded() {
        guard defaults === UserDefaults.standard, !didMigrateLegacy else { return }
        didMigrateLegacy = true
        for album in LocalAlbumStore.shared.albums {
            guard (album.surfaceIds ?? []).contains(ShowCountdownToken.legacyTool)
            else { continue }
            let duration = UserDefaults.standard.integer(
                forKey: CountdownController.durationKey
            )
            let seconds = duration > 0
                ? duration
                : CountdownController.defaultDuration
            let name = nextDefaultName(inShowId: album.id)
            let item = ShowCountdown(
                showId: album.id,
                name: name,
                duration: CountdownController.clampedDuration(seconds)
            )
            countdowns.append(item)
            persist()
            LocalAlbumStore.shared.replaceLegacyCountdownTool(
                with: item.id,
                albumId: album.id
            )
            scheduleSaveIfNeeded(id: item.id)
        }
    }

    private func scheduleSaveIfNeeded(id: UUID) {
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleCountdownSave(id: id)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(countdowns)
            defaults.set(data, forKey: itemsKey)
            defaults.set(Array(syncedIds), forKey: syncedIdsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode countdowns: \(error.localizedDescription)")
        }
    }
}
