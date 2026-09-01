//
//  CameraAlternateStillStore+Sync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - CloudKit upload acknowledgements

extension CameraAlternateStillStore {

    private static let syncedIdsKey = "EclipseTV.camera.syncedCutawayIds"

    /// Cutaways the server has not acknowledged.
    var idsNeedingUpload: [UUID] {
        stills.map(\.id).filter { !syncedIdStrings.contains($0.uuidString) }
    }

    /// Records that CloudKit accepted this still's upload (or it arrived remotely).
    func markSynced(id: UUID) {
        var ids = syncedIdStrings
        guard ids.insert(id.uuidString).inserted else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.syncedIdsKey)
    }

    /// Drops `id` from the synced set (local edit or delete).
    func markNeedsUpload(id: UUID) {
        var ids = syncedIdStrings
        guard ids.remove(id.uuidString) != nil else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.syncedIdsKey)
    }

    /// Marks every cutaway dirty (zone recreate / re-push).
    func markAllNeedsUpload() {
        for id in stills.map(\.id) {
            markNeedsUpload(id: id)
        }
    }

    private var syncedIdStrings: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.syncedIdsKey) ?? [])
    }
}
