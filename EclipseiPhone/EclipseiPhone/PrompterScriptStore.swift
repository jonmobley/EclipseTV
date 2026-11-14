//
//  PrompterScriptStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// One Prompter's script, with its own last-writer-wins clock.
///
/// `showId` is the script's key: the Show's id for a Show's first Prompter (the
/// `prompter-<showId>` record the Mac reads too), or the tile's own id for any extra
/// Prompter in that Show (`ShowToolToken.extraPrompterToken`). The name stays
/// `showId` because it is the stored and synced field name.
///
/// `script == ""` means someone cleared it; no entry at all means no device has
/// written one yet. The clock is stamped only on a real local edit.
struct PrompterScript: Codable, Equatable {
    let showId: UUID
    var script: String
    var modifiedAt: Date
}

/// Persists Prompter scripts (keyed as described on `PrompterScript`) in UserDefaults and syncs them through iCloud
/// as `Prompter` records.
///
/// The record is never given a CloudKit `parent`, so sharing a Show never carries the
/// script to participants (same rule as presenter notes). Scroll speed and text size
/// are per-device settings and live in `PrompterLocalSettings`, not here.
@MainActor
final class PrompterScriptStore {

    static let shared = PrompterScriptStore()

    /// Posted when a script changes; `object` is the Show's `UUID`.
    static let didChangeNotification = Notification.Name("PrompterScriptStore.didChange")

    /// CloudKit records are capped at 1 MB; a script never gets anywhere near that.
    nonisolated static let maxScriptLength = 200_000

    private(set) var entries: [PrompterScript] = []

    private let defaults: UserDefaults
    private let now: () -> Date
    private let itemsKey = "EclipseTV.prompter.scripts"
    private let syncedIdsKey = "EclipseTV.prompter.syncedShowIds"
    private var syncedIds: Set<String> = []
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "PrompterScriptStore"
    )

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        load()
    }

    /// Cuts `text` down to `maxScriptLength` characters.
    nonisolated static func clamped(_ text: String) -> String {
        text.count <= maxScriptLength ? text : String(text.prefix(maxScriptLength))
    }

    // MARK: - Queries

    /// The stored entry for `showId`, if any device has written one.
    func entry(forShowId showId: UUID) -> PrompterScript? {
        entries.first { $0.showId == showId }
    }

    /// The script for `showId`; `""` when none.
    func script(forShowId showId: UUID) -> String {
        entry(forShowId: showId)?.script ?? ""
    }

    /// Whether `showId` has a non-empty script.
    func hasScript(forShowId showId: UUID) -> Bool {
        !script(forShowId: showId).isEmpty
    }

    // MARK: - Local edits

    /// Stores a locally edited script and schedules its upload.
    ///
    /// Clearing a script keeps an empty entry so the clear reaches other devices.
    /// Clearing a Show that never had one is a no-op.
    func setScript(_ text: String, forShowId showId: UUID) {
        let next = Self.clamped(text)
        if let index = entries.firstIndex(where: { $0.showId == showId }) {
            guard entries[index].script != next else { return }
            entries[index].script = next
            entries[index].modifiedAt = now()
        } else {
            guard !next.isEmpty else { return }
            entries.append(PrompterScript(showId: showId, script: next, modifiedAt: now()))
        }
        // A fresh edit is unacknowledged until the server accepts it again.
        syncedIds.remove(showId.uuidString)
        persist(changedShowId: showId)
        scheduleSaveIfNeeded(showId: showId)
    }

    // MARK: - Remote

    /// Applies a script from iCloud when it is at least as new as the local one.
    ///
    /// Returns `false` when the local edit is newer; that entry stays unacknowledged,
    /// so it is re-uploaded and wins on the other devices.
    @discardableResult
    func applyRemote(_ incoming: PrompterScript) -> Bool {
        let entry = PrompterScript(
            showId: incoming.showId,
            script: Self.clamped(incoming.script),
            modifiedAt: incoming.modifiedAt
        )
        if let index = entries.firstIndex(where: { $0.showId == entry.showId }) {
            guard entry.modifiedAt >= entries[index].modifiedAt else { return false }
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        syncedIds.insert(entry.showId.uuidString)
        persist(changedShowId: entry.showId)
        return true
    }

    /// Drops the entry after a CloudKit tombstone without echoing a delete.
    func purgeRemote(showId: UUID) {
        guard entries.contains(where: { $0.showId == showId }) else { return }
        entries.removeAll { $0.showId == showId }
        syncedIds.remove(showId.uuidString)
        persist(changedShowId: showId)
    }

    /// Removes every Prompter script of a deleted Show: its first Prompter's (keyed
    /// by the Show id) and the extra ones in `extraScriptIds`.
    ///
    /// Extra scripts are deleted from iCloud even while applying a remote Show
    /// deletion: the Mac only knows the first Prompter, so a Show deleted there
    /// would otherwise leave the extra records behind forever.
    func deleteAll(forShowId showId: UUID, extraScriptIds: [UUID]) {
        deleteAll(forShowId: showId)
        for scriptId in extraScriptIds where scriptId != showId {
            if entries.contains(where: { $0.showId == scriptId }) {
                entries.removeAll { $0.showId == scriptId }
                syncedIds.remove(scriptId.uuidString)
                persist(changedShowId: scriptId)
            }
            EclipseSyncController.shared.backend.schedulePrompterDelete(showId: scriptId)
        }
    }

    /// Removes the script when its Show is deleted (locally or by a remote tombstone).
    func deleteAll(forShowId showId: UUID) {
        guard entries.contains(where: { $0.showId == showId }) else { return }
        entries.removeAll { $0.showId == showId }
        syncedIds.remove(showId.uuidString)
        persist(changedShowId: showId)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.schedulePrompterDelete(showId: showId)
    }

    // MARK: - Upload bookkeeping

    /// Forgets every upload acknowledgement (zone loss, iCloud account switch).
    func markAllNeedsUpload() {
        guard !syncedIds.isEmpty else { return }
        syncedIds.removeAll()
        defaults.set(Array(syncedIds), forKey: syncedIdsKey)
    }

    /// Records that the backend accepted this Show's script.
    func markSynced(showId: UUID) {
        guard !syncedIds.contains(showId.uuidString) else { return }
        syncedIds.insert(showId.uuidString)
        defaults.set(Array(syncedIds), forKey: syncedIdsKey)
    }

    /// Shows whose script the server has not acknowledged yet.
    var idsNeedingUpload: [UUID] {
        entries.filter { !syncedIds.contains($0.showId.uuidString) }.map(\.showId)
    }

    // MARK: - Persistence

    private func load() {
        syncedIds = Set(defaults.stringArray(forKey: syncedIdsKey) ?? [])
        entries = SalvagingListDecoder.decodeList(
            PrompterScript.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    private func scheduleSaveIfNeeded(showId: UUID) {
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.schedulePrompterSave(showId: showId)
    }

    private func persist(changedShowId: UUID) {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: itemsKey)
            defaults.set(Array(syncedIds), forKey: syncedIdsKey)
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: changedShowId
            )
        } catch {
            logger.error("Failed to encode prompter scripts: \(error.localizedDescription)")
        }
    }
}
