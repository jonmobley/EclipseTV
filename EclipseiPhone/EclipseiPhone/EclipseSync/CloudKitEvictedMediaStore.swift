//
//  CloudKitEvictedMediaStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// MediaItems whose local copy the user removed on purpose.
///
/// `.remoteOnly` alone cannot express this: it means both "this device never had
/// the file" and "the user reclaimed the space". Fetched records arrive with their
/// asset bytes attached, so without this distinction any later edit to an item —
/// made on any device — would silently re-materialise a download the user had just
/// deleted. Cleared when the user asks for the file again.
@MainActor
final class CloudKitEvictedMediaStore {

    private var ids: Set<String> = []
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "EclipseTV.cloudKit.evictedMedia"
    ) {
        self.defaults = defaults
        self.key = key
        ids = Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Whether the user deliberately removed the local copy of `recordName`.
    func contains(_ recordName: String) -> Bool { ids.contains(recordName) }

    /// Records that the local copy of `recordName` was removed by the user.
    func note(_ recordName: String) {
        guard ids.insert(recordName).inserted else { return }
        persist()
    }

    /// Forgets the eviction, so the file may be kept again.
    func clear(_ recordName: String) {
        guard ids.remove(recordName) != nil else { return }
        persist()
    }

    func removeAll() {
        guard !ids.isEmpty else { return }
        ids = []
        persist()
    }

    private func persist() {
        defaults.set(Array(ids), forKey: key)
    }
}
