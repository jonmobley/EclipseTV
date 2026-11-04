//
//  ShowToolTokenPrompterTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct ShowToolTokenPrompterTests {

    private func makeStore() throws -> LocalAlbumStore {
        let suite = "PrompterToken.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return LocalAlbumStore(defaults: defaults)
    }

    @Test func prompterIsAnOptInToolNotADefault() {
        #expect(ShowToolToken.isTool(ShowToolToken.prompter))
        #expect(ShowToolToken.optional.contains(ShowToolToken.prompter))
        #expect(!ShowToolToken.all.contains(ShowToolToken.prompter))
        #expect(ShowToolToken.title(for: ShowToolToken.prompter) == "Prompter")
        #expect(ShowToolToken.systemImage(for: ShowToolToken.prompter) != nil)
    }

    @Test func newShowOffersPrompterUntilAdded() throws {
        let store = try makeStore()
        let show = try store.create(name: "Talk", orientation: .landscape)
        var album = try #require(store.album(id: show.id))
        #expect(album.addableOptionalToolTokens.contains(ShowToolToken.prompter))
        #expect(!album.resolvedSurfaceIds.contains(ShowToolToken.prompter))

        store.showTool(ShowToolToken.prompter, albumId: show.id)
        album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.last == ShowToolToken.prompter)
        #expect(!album.addableOptionalToolTokens.contains(ShowToolToken.prompter))

        store.hideTool(ShowToolToken.prompter, albumId: show.id)
        album = try #require(store.album(id: show.id))
        #expect(!album.resolvedSurfaceIds.contains(ShowToolToken.prompter))
        #expect(album.addableOptionalToolTokens.contains(ShowToolToken.prompter))
    }

    @Test func sanitizedSurfaceKeepsPrompterToken() {
        let surface = [ShowToolToken.camera, ShowToolToken.prompter, "photo.jpg"]
        let cleaned = LocalAlbum.sanitizedSurface(surface, itemIds: ["photo.jpg"])
        #expect(cleaned == surface)
    }

    @Test func mergeShowsKeepsPrompterTokenFromEitherSide() {
        let id = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let local = LocalAlbum(
            id: id, name: "Talk",
            surfaceIds: [ShowToolToken.camera, ShowToolToken.prompter]
        )
        let remote = LocalAlbum(
            id: id, name: "Talk",
            surfaceIds: [ShowToolToken.camera]
        )
        let merged = CloudKitConflictResolver.mergeShows(
            local: local, localModified: base,
            remote: remote, remoteModified: base.addingTimeInterval(5)
        )
        #expect(merged.resolvedSurfaceIds.contains(ShowToolToken.prompter))
    }
}
