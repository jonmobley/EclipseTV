//
//  CloudKitConflictResolver.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Merge rules for concurrent Show edits across devices.
///
/// Scalars (name, cover, orientation, practice preview) are last-writer-wins
/// by `modifiedAt`.
/// Membership is union-then-reorder minus ids whose latest tombstone event is a
/// removal (`SyncTombstones`), so an add is never lost, a remove is not
/// resurrected by an older copy, and Undo / re-add after a synced remove holds.
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

    /// Drops ids whose latest tombstone event is a removal.
    static func subtractingTombstones(
        _ ids: [String],
        tombstones: [String]
    ) -> [String] {
        let dead = SyncTombstones.removedIds(tombstones)
        return ids.filter { !dead.contains($0) }
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
        let deletedItems = SyncTombstones.merge(
            base.deletedItemIds, other.deletedItemIds
        )
        let deletedSurface = SyncTombstones.merge(
            base.deletedSurfaceIds, other.deletedSurfaceIds
        )
        merged.deletedItemIds = deletedItems
        merged.deletedSurfaceIds = deletedSurface
        merged.itemIds = subtractingTombstones(
            unionMembership(
                preferredOrder: base.itemIds,
                other: other.itemIds
            ),
            tombstones: deletedItems
        )
        if base.surfaceIds == nil, other.surfaceIds == nil {
            merged.surfaceIds = nil
        } else {
            let preferred = base.resolvedSurfaceIds
            let otherSurface = other.resolvedSurfaceIds
            let union = subtractingTombstones(
                unionMembership(
                    preferredOrder: preferred, other: otherSurface
                ),
                tombstones: deletedSurface + deletedItems
            )
            let slideshows = union.filter(ShowSlideshowToken.isSlideshow)
            let countdowns = union.filter(ShowCountdownToken.isCountdown)
            let livePolls = union.filter(ShowLivePollToken.isLivePoll)
            merged.surfaceIds = LocalAlbum.sanitizedSurface(
                union,
                itemIds: merged.itemIds,
                slideshowIds: slideshows,
                countdownIds: countdowns,
                livePollIds: livePolls
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
