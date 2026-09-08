//
//  CloudKitShowDirtyStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Tracks which Shows have local edits CloudKit has not accepted yet.
///
/// Bootstrap and every foreground call `enqueueAllLocal`, so enqueueing *every*
/// Show there re-uploaded the whole Show list on each foreground and made the
/// first save of each one a rejected insert. Only genuinely dirty Shows belong in
/// the queue.
@MainActor
final class CloudKitShowDirtyStore {

    private var ids: Set<String> = []
    private var isSeeded: Bool
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "EclipseTV.cloudKit.showsNeedingUpload"
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

    /// Marks every existing Show dirty exactly once.
    ///
    /// Installs that predate dirty tracking have no stored set; without this their
    /// Shows would never be enqueued again and would silently stop syncing.
    func seedIfNeeded(with showIds: [UUID]) {
        guard !isSeeded else { return }
        isSeeded = true
        ids = Set(showIds.map(\.uuidString))
        persist()
    }

    /// Whether `id` has unsent local changes.
    func contains(_ id: UUID) -> Bool { ids.contains(id.uuidString) }

    /// Flags `id` for upload after a local edit.
    func markDirty(_ id: UUID) {
        guard ids.insert(id.uuidString).inserted else { return }
        persist()
    }

    /// Clears `id` once CloudKit accepts its save.
    func markClean(_ id: UUID) {
        guard ids.remove(id.uuidString) != nil else { return }
        persist()
    }

    /// Flags every Show for upload (zone loss, account switch).
    func markAllDirty(_ showIds: [UUID]) {
        isSeeded = true
        ids = Set(showIds.map(\.uuidString))
        persist()
    }

    private func persist() {
        defaults.set(Array(ids), forKey: key)
    }
}
