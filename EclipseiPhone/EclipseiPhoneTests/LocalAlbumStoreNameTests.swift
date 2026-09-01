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

    @Test func sanitizedSurfaceAppendsSlideshowsLast() {
        let token = ShowSlideshowToken.token(for: UUID())
        let result = LocalAlbum.sanitizedSurface(
            ShowToolToken.all + ["a"],
            itemIds: ["a"],
            slideshowIds: [token]
        )
        #expect(result == ShowToolToken.all + ["a", token])
    }

    @Test func sanitizedSurfaceKeepsSlideshowSlot() {
        let token = ShowSlideshowToken.token(for: UUID())
        let result = LocalAlbum.sanitizedSurface(
            [token, ShowToolToken.screensaver, "a"],
            itemIds: ["a"],
            slideshowIds: [token]
        )
        #expect(result == [token, ShowToolToken.screensaver, "a"])
    }

    @Test func reorderSurfaceMovesSlideshowAmongMembers() throws {
        let store = makeStore()
        let show = try store.create(name: "Slideshows", orientation: .landscape)
        store.add(itemId: "a", toAlbumId: show.id)
        let token = ShowSlideshowToken.token(for: UUID())
        store.reorderSurface(
            [ShowToolToken.logo, token, "a", ShowToolToken.screensaver],
            albumId: show.id
        )
        let album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds == [
            ShowToolToken.logo, token, "a", ShowToolToken.screensaver
        ])
        #expect(album.itemIds == ["a"])
        #expect(!album.itemIds.contains(token))
    }

    @Test func slideshowTokenRoundTrips() {
        let id = UUID()
        let token = ShowSlideshowToken.token(for: id)
        #expect(ShowSlideshowToken.isSlideshow(token))
        #expect(!ShowSlideshowToken.isSlideshow("media-1"))
        #expect(ShowSlideshowToken.slideshowId(from: token) == id)
        #expect(ShowSlideshowToken.slideshowId(from: "media-1") == nil)
    }

    @Test func addSlideshowAppendsWhenSurfaceMaterialized() throws {
        let store = makeStore()
        let show = try store.create(name: "Deck", orientation: .landscape)
        store.hideTool(ShowToolToken.camera, albumId: show.id)
        let slideshowId = UUID()
        store.addSlideshow(slideshowId, toAlbumId: show.id)
        let album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.last == ShowSlideshowToken.token(for: slideshowId))
    }

    @Test func livePollTokenRoundTrips() {
        let id = UUID()
        let token = ShowLivePollToken.token(for: id)
        #expect(ShowLivePollToken.isLivePoll(token))
        #expect(!ShowLivePollToken.isLivePoll("media-1"))
        #expect(ShowLivePollToken.livePollId(from: token) == id)
        #expect(ShowLivePollToken.livePollId(from: "media-1") == nil)
    }

    @Test func sanitizedSurfaceAppendsLivePollsLast() {
        let token = ShowLivePollToken.token(for: UUID())
        let result = LocalAlbum.sanitizedSurface(
            ShowToolToken.all + ["a"],
            itemIds: ["a"],
            livePollIds: [token]
        )
        #expect(result == ShowToolToken.all + ["a", token])
    }

    @Test func addLivePollAppendsWhenSurfaceMaterialized() throws {
        let store = makeStore()
        let show = try store.create(name: "Polls", orientation: .landscape)
        store.hideTool(ShowToolToken.camera, albumId: show.id)
        let pollId = UUID()
        store.addLivePoll(pollId, toAlbumId: show.id)
        let album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.last == ShowLivePollToken.token(for: pollId))
        #expect(!album.itemIds.contains(ShowLivePollToken.token(for: pollId)))
    }
}
