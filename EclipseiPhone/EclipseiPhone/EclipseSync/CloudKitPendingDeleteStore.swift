//
//  CloudKitPendingDeleteStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Durable list of record names whose CloudKit delete has not been acknowledged.
///
/// Saves survive a missing engine because every store keeps a dirty flag that
/// bootstrap re-derives. Deletes have no such flag: the local object is already
/// gone, so a delete dropped while the engine was nil (signed out, or the async
/// window before `bootstrapEngineIfPossible` finishes) leaves the server copy
/// alive — and the next fetch re-inserts the object the user deleted.
///
/// Names are recorded before the engine is consulted and cleared only once
/// CloudKit confirms the delete (or reports the record already gone).
@MainActor
final class CloudKitPendingDeleteStore {

    private var names: Set<String>
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "EclipseTV.cloudKit.pendingDeletes"
    ) {
        self.defaults = defaults
        self.key = key
        names = Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Record names still awaiting a confirmed server delete.
    var recordNames: [String] { Array(names) }

    /// Records that `recordName` must be deleted server-side.
    func note(_ recordName: String) {
        guard names.insert(recordName).inserted else { return }
        persist()
    }

    /// Clears `recordName` after CloudKit confirms the delete, or when a fresh
    /// save supersedes it (singleton records can be cleared and set again).
    func clear(_ recordName: String) {
        guard names.remove(recordName) != nil else { return }
        persist()
    }

    /// Drops every entry (account switch — the new account owes us nothing).
    func removeAll() {
        guard !names.isEmpty else { return }
        names.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(Array(names), forKey: key)
    }
}
