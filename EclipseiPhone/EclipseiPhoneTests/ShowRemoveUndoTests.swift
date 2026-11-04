//
//  ShowRemoveUndoTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct ShowRemoveUndoTests {

    @Test func restoringASnapshotPutsItemsBackInOrder() throws {
        let suite = "ShowRemoveUndoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = LocalAlbumStore(defaults: defaults)
        let show = try store.create(name: "Undo test")
        for id in ["a", "b", "c"] {
            store.add(itemId: id, toAlbumId: show.id)
        }
        let snapshot = try #require(store.albums.first { $0.id == show.id })

        store.remove(itemId: "b", fromAlbumId: show.id)
        #expect(store.albums.first { $0.id == show.id }?.itemIds == ["a", "c"])
        let removed = try #require(store.albums.first { $0.id == show.id })
        #expect(SyncTombstones.isRemoved("b", in: removed.deletedItemIds))

        store.restoreMembership(from: snapshot)
        let restored = try #require(store.albums.first { $0.id == show.id })
        #expect(restored.itemIds == ["a", "b", "c"])
        #expect(!SyncTombstones.isRemoved("b", in: restored.deletedItemIds))
    }

    /// Undo after another device already merged the removal must hold
    /// through the next sync in both directions (audit 2026-11-02, B-1).
    @Test func undoSurvivesAMergeWithACopyThatSawTheRemoval() throws {
        let suite = "ShowRemoveUndoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = LocalAlbumStore(defaults: defaults)
        let show = try store.create(name: "Undo sync test")
        for id in ["a", "b"] {
            store.add(itemId: id, toAlbumId: show.id)
        }
        let snapshot = try #require(store.albums.first { $0.id == show.id })
        store.remove(itemId: "b", fromAlbumId: show.id)
        let otherDevice = try #require(store.albums.first { $0.id == show.id })

        store.restoreMembership(from: snapshot)
        let undone = try #require(store.albums.first { $0.id == show.id })
        let older = Date(timeIntervalSince1970: 1)
        let newer = Date(timeIntervalSince1970: 2)
        let onOther = CloudKitConflictResolver.mergeShows(
            local: otherDevice, localModified: newer, remote: undone, remoteModified: older
        )
        #expect(onOther.itemIds.contains("b"))
        let backHere = CloudKitConflictResolver.mergeShows(
            local: undone, localModified: older, remote: onOther, remoteModified: newer
        )
        #expect(backHere.itemIds.contains("b"))
    }
}
