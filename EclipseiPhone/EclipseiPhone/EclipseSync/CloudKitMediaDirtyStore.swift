//
//  CloudKitMediaDirtyStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Tracks MediaItem records whose *metadata* CloudKit has not accepted yet.
///
/// Fit mode, custom framing, loop, and mute live on the MediaItem record but are
/// written by plain settings helpers. Enqueueing every capture on each foreground
/// was the only thing carrying those edits, and it was expensive in three ways:
/// `makeMediaRecord` stamps a fresh `modifiedAt`, so every foreground rewrote every
/// record, every other device then re-fetched those records *with their assets* and
/// discarded the bytes, and `applyRemoteMediaPrefs` has no clock — so an idle device
/// foregrounding overwrote preference edits made on another one.
///
/// Ids here are MediaItem record names (capture `id` / import `cloudId`), which is
/// also why this is keyed by `String` rather than `UUID` like the Show equivalent.
@MainActor
final class CloudKitMediaDirtyStore {

    private var ids: Set<String> = []
    private var isSeeded: Bool
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "EclipseTV.cloudKit.mediaNeedingUpload"
    ) {
        self.defaults = defaults
        self.key = key
        if let raw = defaults.stringArray(forKey: key) {
            ids = Set(raw)
            isSeeded = true
        } else {
            isSeeded = false
        }
    }

    /// Record names with unsent metadata edits.
    var allDirty: [String] { Array(ids) }

    /// Marks every known record dirty exactly once.
    ///
    /// Installs that predate dirty tracking relied on the blanket re-enqueue, so
    /// without a one-time seed their local Fit / framing / loop / mute edits would
    /// never reach CloudKit again. Costs a single round of saves, then settles.
    func seedIfNeeded(with recordNames: [String]) {
        guard !isSeeded else { return }
        isSeeded = true
        ids = Set(recordNames)
        persist()
    }

    /// Whether `recordName` has unsent local changes.
    func contains(_ recordName: String) -> Bool { ids.contains(recordName) }

    /// Flags `recordName` for a metadata upload after a local edit.
    func markDirty(_ recordName: String) {
        guard ids.insert(recordName).inserted else { return }
        persist()
    }

    /// Clears `recordName` once CloudKit accepts its save.
    func markClean(_ recordName: String) {
        guard ids.remove(recordName) != nil else { return }
        persist()
    }

    /// Flags every known record for upload (zone loss, account switch).
    func markAllDirty(_ recordNames: [String]) {
        isSeeded = true
        ids = Set(recordNames)
        persist()
    }

    /// Drops all tracking without scheduling anything.
    func removeAll() {
        guard !ids.isEmpty else { return }
        ids = []
        persist()
    }

    private func persist() {
        defaults.set(Array(ids), forKey: key)
    }
}
