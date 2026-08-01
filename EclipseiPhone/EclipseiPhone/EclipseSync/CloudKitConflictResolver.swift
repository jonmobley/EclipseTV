//
//  CloudKitConflictResolver.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Merge rules for concurrent Show edits across devices.
///
/// Scalars (name, cover, orientation) are last-writer-wins by `modifiedAt`.
/// Membership is union-then-reorder so an item added on one device is never lost.
enum CloudKitConflictResolver {

    /// Merged membership: union of both sides, preferring `preferredOrder` sequence,
    /// then appending any leftovers from `other` in their relative order.
    static func unionMembership(
        preferredOrder: [String],
        other: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in preferredOrder where seen.insert(id).inserted {
            result.append(id)
        }
        for id in other where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// Picks the newer Show fields, then unions membership and surface layout.
    static func mergeShows(
        local: LocalAlbum,
        localModified: Date,
        remote: LocalAlbum,
        remoteModified: Date
    ) -> LocalAlbum {
        let preferRemote = remoteModified >= localModified
        let base = preferRemote ? remote : local
        let other = preferRemote ? local : remote
        var merged = base
        merged.itemIds = unionMembership(
            preferredOrder: base.itemIds,
            other: other.itemIds
        )
        if base.surfaceIds == nil, other.surfaceIds == nil {
            merged.surfaceIds = nil
        } else {
            let preferred = base.resolvedSurfaceIds
            let otherSurface = other.resolvedSurfaceIds
            merged.surfaceIds = LocalAlbum.sanitizedSurface(
                unionMembership(preferredOrder: preferred, other: otherSurface),
                itemIds: merged.itemIds
            )
        }
        if let cover = merged.coverId, !merged.itemIds.contains(cover) {
            merged.coverId = merged.itemIds.first
        }
        return merged
    }

    /// Newer capture metadata wins; never clear a local content hash with nil.
    static func mergeCaptures(
        local: CaptureRecord,
        remote: CaptureRecord,
        preferRemote: Bool
    ) -> CaptureRecord {
        var winner = preferRemote ? remote : local
        let loser = preferRemote ? local : remote
        if winner.contentHash == nil {
            winner.contentHash = loser.contentHash
        }
        if winner.showId == nil {
            winner.showId = loser.showId
        }
        // Keep local file presence: if we have bytes, we are not remote-only.
        if local.syncState != .remoteOnly, preferRemote {
            winner.syncState = local.syncState == .downloading
                ? .downloading
                : (local.syncState == .pendingUpload ? .pendingUpload : .synced)
        }
        return winner
    }
}
