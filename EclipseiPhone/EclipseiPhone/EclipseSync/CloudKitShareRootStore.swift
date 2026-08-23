//
//  CloudKitShareRootStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Persists Show ids that are CloudKit `CKShare` roots.
///
/// Child records may set `CKRecord.parent` only for these ids. Unshared Shows
/// keep membership in the `showId` field alone.
@MainActor
final class CloudKitShareRootStore {

    private let defaults: UserDefaults
    private let key: String
    private var ids: Set<UUID>

    /// Loads previously marked share roots from `defaults`.
    init(
        defaults: UserDefaults = .standard,
        key: String = "EclipseTV.cloudKit.shareRootIds"
    ) {
        self.defaults = defaults
        self.key = key
        let raw = defaults.stringArray(forKey: key) ?? []
        ids = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    /// Whether `id` is a known share root.
    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// Marks `id` as a share root. Returns `true` if it was newly added.
    @discardableResult
    func mark(_ id: UUID) -> Bool {
        guard ids.insert(id).inserted else { return false }
        persist()
        return true
    }

    /// Forgets `id` as a share root. Returns `true` if it was present.
    @discardableResult
    func unmark(_ id: UUID) -> Bool {
        guard ids.remove(id) != nil else { return false }
        persist()
        return true
    }

    /// Membership field and whether CloudKit `parent` should be set.
    func resolve(
        preferredShowId: UUID?,
        containingShowIds: [UUID]
    ) -> (showId: UUID?, attachAsShareChild: Bool) {
        CloudKitShareMembership.resolve(
            preferredShowId: preferredShowId,
            containingShowIds: containingShowIds,
            shareRootIds: ids
        )
    }

    private func persist() {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}

/// Pure picker for CloudKit Show membership vs share `parent`.
enum CloudKitShareMembership {

    /// Prefers a known share root so a `CKShare` carries its children.
    ///
    /// Unshared Shows still get a `showId` field (preferred, else first
    /// containing album) with `attachAsShareChild == false`.
    static func resolve(
        preferredShowId: UUID?,
        containingShowIds: [UUID],
        shareRootIds: Set<UUID>
    ) -> (showId: UUID?, attachAsShareChild: Bool) {
        let candidates = orderedUnique(
            preferred: preferredShowId,
            rest: containingShowIds
        )
        if let root = candidates.first(where: { shareRootIds.contains($0) }) {
            return (root, true)
        }
        return (candidates.first, false)
    }

    private static func orderedUnique(
        preferred: UUID?,
        rest: [UUID]
    ) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in [preferred].compactMap({ $0 }) + rest where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
