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
        #expect(store.albums.first { $0.id == show.id }?.deletedItemIds.contains("b") == true)

        store.restoreMembership(from: snapshot)
        let restored = try #require(store.albums.first { $0.id == show.id })
        #expect(restored.itemIds == ["a", "b", "c"])
        #expect(!restored.deletedItemIds.contains("b"))
    }
}
