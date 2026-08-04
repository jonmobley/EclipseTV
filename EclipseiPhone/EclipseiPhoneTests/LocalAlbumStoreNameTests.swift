//
//  LocalAlbumStoreNameTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct LocalAlbumStoreNameTests {

    private func makeStore() -> LocalAlbumStore {
        let suite = "LocalAlbumStoreNameTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LocalAlbumStore(defaults: defaults)
    }

    @Test func createRejectsDuplicateName() throws {
        let store = makeStore()
        _ = try store.create(name: "Beach", orientation: .landscape)
        #expect(throws: LocalAlbumStore.StoreError.nameTaken) {
            try store.create(name: "beach", orientation: .portrait)
        }
    }

    @Test func renameAllowsSameNameOnSelf() throws {
        let store = makeStore()
        let show = try store.create(name: "Beach", orientation: .landscape)
        try store.rename(id: show.id, to: "Beach")
        #expect(store.album(id: show.id)?.name == "Beach")
    }

    @Test func renameRejectsNameTakenByOther() throws {
        let store = makeStore()
        _ = try store.create(name: "One", orientation: .landscape)
        let two = try store.create(name: "Two", orientation: .landscape)
        #expect(throws: LocalAlbumStore.StoreError.nameTaken) {
            try store.rename(id: two.id, to: "one")
        }
    }

    @Test func uniquifiedNameAddsNumericSuffix() throws {
        let store = makeStore()
        _ = try store.create(name: "Shared", orientation: .landscape)
        #expect(store.uniquifiedName("Shared") == "Shared (2)")
        _ = try store.create(name: "Shared (2)", orientation: .landscape)
        #expect(store.uniquifiedName("Shared") == "Shared (3)")
    }

    @Test func applySyncedUniquifiesJoinedCollision() throws {
        let store = makeStore()
        _ = try store.create(name: "Party", orientation: .landscape)
        let joined = LocalAlbum(name: "Party", orientation: .landscape)
        store.applySynced(joined, modifiedAt: Date())
        #expect(store.album(id: joined.id)?.name == "Party (2)")
    }

    @Test func applySyncedKeepsNameWhenFree() {
        let store = makeStore()
        let joined = LocalAlbum(name: "Unique", orientation: .portrait)
        store.applySynced(joined, modifiedAt: Date())
        #expect(store.album(id: joined.id)?.name == "Unique")
    }

    @Test func defaultSurfaceIsToolsThenMembers() throws {
        let store = makeStore()
        let show = try store.create(name: "Tools", orientation: .landscape)
        store.add(itemId: "media-1", toAlbumId: show.id)
        let album = try #require(store.album(id: show.id))
        #expect(album.surfaceIds == nil)
        #expect(album.resolvedSurfaceIds == ShowToolToken.all + ["media-1"])
    }

    @Test func hideAndShowToolMaterializesSurface() throws {
        let store = makeStore()
        let show = try store.create(name: "Hide", orientation: .landscape)
        store.hideTool(ShowToolToken.camera, albumId: show.id)
        var album = try #require(store.album(id: show.id))
        #expect(album.surfaceIds != nil)
        #expect(!album.resolvedSurfaceIds.contains(ShowToolToken.camera))
        #expect(album.missingToolTokens == [ShowToolToken.camera])
        #expect(album.itemIds.isEmpty)

        store.showTool(ShowToolToken.camera, albumId: show.id)
        album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.last == ShowToolToken.camera)
        #expect(album.missingToolTokens.isEmpty)
    }

    @Test func reorderSurfaceMovesToolsAmongMembers() throws {
        let store = makeStore()
        let show = try store.create(name: "Reorder", orientation: .landscape)
        store.add(itemId: "a", toAlbumId: show.id)
        store.add(itemId: "b", toAlbumId: show.id)
        store.reorderSurface(
            ["a", ShowToolToken.logo, "b", ShowToolToken.screensaver],
            albumId: show.id
        )
        let album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds == [
            "a", ShowToolToken.logo, "b", ShowToolToken.screensaver
        ])
        #expect(album.itemIds == ["a", "b"])
    }
}
