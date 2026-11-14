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

    // MARK: - Several Prompters in one Show

    @Test func firstPrompterUsesShowIdAndExtrasUseTheirOwn() {
        let showId = UUID()
        let extraId = UUID()
        let extra = ShowToolToken.extraPrompterToken(scriptId: extraId)
        #expect(extra.hasPrefix(ShowToolToken.prefix))
        #expect(ShowToolToken.isTool(extra))
        #expect(ShowToolToken.isPrompter(extra))
        #expect(ShowToolToken.isPrompter(ShowToolToken.prompter))
        #expect(!ShowToolToken.isPrompter(ShowToolToken.camera))
        #expect(!ShowToolToken.isPrompter(ShowToolToken.extraPrompterPrefix + "nope"))
        #expect(ShowToolToken.prompterScriptId(from: ShowToolToken.prompter, showId: showId) == showId)
        #expect(ShowToolToken.prompterScriptId(from: extra, showId: showId) == extraId)
        #expect(ShowToolToken.prompterToken(scriptId: showId, showId: showId) == ShowToolToken.prompter)
        #expect(ShowToolToken.prompterToken(scriptId: extraId, showId: showId) == extra)
        #expect(
            ShowToolToken.prompterScriptIds(
                in: [ShowToolToken.camera, ShowToolToken.prompter, "a.jpg", extra], showId: showId
            ) == [showId, extraId]
        )
    }

    @Test func showHoldsSeveralPrompters() throws {
        let store = try makeStore()
        let show = try store.create(name: "Talk", orientation: .landscape)
        let extra = ShowToolToken.extraPrompterToken(scriptId: UUID())
        store.showTool(ShowToolToken.prompter, albumId: show.id)
        store.showTool(extra, albumId: show.id)
        var album = try #require(store.album(id: show.id))
        #expect(Array(album.resolvedSurfaceIds.suffix(2)) == [ShowToolToken.prompter, extra])

        store.hideTool(extra, albumId: show.id)
        album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.contains(ShowToolToken.prompter))
        #expect(!album.resolvedSurfaceIds.contains(extra))
    }

    @Test func sanitizedSurfaceKeepsExtraPrompterTokens() {
        let extra = ShowToolToken.extraPrompterToken(scriptId: UUID())
        let surface = [ShowToolToken.prompter, extra, "photo.jpg"]
        #expect(LocalAlbum.sanitizedSurface(surface, itemIds: ["photo.jpg"]) == surface)
    }

    @Test func liveProgramLightsOnlyThePrompterOnScreen() {
        let showId = UUID()
        let extraId = UUID()
        let first = ShowGridItem.prompter(token: ShowToolToken.prompter, scriptId: showId)
        let second = ShowGridItem.prompter(
            token: ShowToolToken.extraPrompterToken(scriptId: extraId), scriptId: extraId
        )
        let program = ShowProgram(kind: .prompter, itemId: extraId.uuidString)
        #expect(program.matches(second))
        #expect(!program.matches(first))
        // An older director sends no id: both read as live rather than neither.
        let legacy = ShowProgram(kind: .prompter)
        #expect(legacy.matches(first) && legacy.matches(second))
    }

    @Test func deletingAShowRemovesEveryPrompterScript() throws {
        let suite = "PrompterScripts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let scripts = PrompterScriptStore(defaults: defaults)
        let showId = UUID()
        let extraId = UUID()
        let otherId = UUID()
        scripts.setScript("Opening", forShowId: showId)
        scripts.setScript("Keynote", forShowId: extraId)
        scripts.setScript("Other show", forShowId: otherId)
        scripts.deleteAll(forShowId: showId, extraScriptIds: [showId, extraId])
        #expect(!scripts.hasScript(forShowId: showId))
        #expect(!scripts.hasScript(forShowId: extraId))
        #expect(scripts.script(forShowId: otherId) == "Other show")
    }
}
