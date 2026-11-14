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
        let extraId = ShowToolToken.newExtraPrompterScriptId()
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
        let extra = ShowToolToken.extraPrompterToken(scriptId: ShowToolToken.newExtraPrompterScriptId())
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
        let extra = ShowToolToken.extraPrompterToken(scriptId: ShowToolToken.newExtraPrompterScriptId())
        let surface = [ShowToolToken.prompter, extra, "photo.jpg"]
        #expect(LocalAlbum.sanitizedSurface(surface, itemIds: ["photo.jpg"]) == surface)
    }

    @Test func liveProgramLightsOnlyThePrompterOnScreen() {
        let showId = UUID()
        let extraId = ShowToolToken.newExtraPrompterScriptId()
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
        let extraId = ShowToolToken.newExtraPrompterScriptId()
        let otherId = UUID()
        scripts.setScript("Opening", forShowId: showId)
        scripts.setScript("Keynote", forShowId: extraId)
        scripts.setScript("Other show", forShowId: otherId)
        scripts.deleteAll(forShowId: showId, extraScriptIds: [showId, extraId])
        #expect(!scripts.hasScript(forShowId: showId))
        #expect(!scripts.hasScript(forShowId: extraId))
        #expect(scripts.script(forShowId: otherId) == "Other show")
    }

    @Test func showDeletesOnlyExtraPromptersItOwns() {
        let ownId = UUID()
        let mineId = ShowToolToken.newExtraPrompterScriptId()
        let otherShowId = UUID()
        let sharedScriptId = ShowToolToken.newExtraPrompterScriptId()
        let show = LocalAlbum(id: ownId, name: "A", surfaceIds: [
            ShowToolToken.prompter,
            ShowToolToken.extraPrompterToken(scriptId: mineId),
            ShowToolToken.extraPrompterToken(scriptId: otherShowId),
            ShowToolToken.extraPrompterToken(scriptId: sharedScriptId),
            ShowToolToken.extraPrompterToken(scriptId: ownId)
        ])
        let other = LocalAlbum(id: otherShowId, name: "B", surfaceIds: [
            ShowToolToken.extraPrompterToken(scriptId: sharedScriptId)
        ])
        #expect(LocalAlbumStore.ownedExtraPrompterScriptIds(of: show, among: [other]) == [mineId])
        #expect(LocalAlbumStore.ownedExtraPrompterScriptIds(of: nil, among: [other]).isEmpty)
    }

    @Test func extraPrompterIdsNeverLookLikeShowIds() {
        let extra = ShowToolToken.newExtraPrompterScriptId()
        #expect(ShowToolToken.isExtraPrompterScriptId(extra))
        #expect(UUID(uuidString: extra.uuidString) == extra)
        // Shows get random version-4 ids, which never parse as an extra Prompter.
        for _ in 0..<50 {
            let showId = UUID()
            #expect(!ShowToolToken.isExtraPrompterScriptId(showId))
            let planted = ShowToolToken.extraPrompterToken(scriptId: showId)
            #expect(!ShowToolToken.isPrompter(planted))
            #expect(ShowToolToken.prompterScriptId(from: planted, showId: UUID()) == nil)
        }
    }

    @Test func deleteAllNeverTouchesAShowShapedScript() throws {
        let suite = "PrompterScripts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let scripts = PrompterScriptStore(defaults: defaults)
        let showId = UUID()
        let otherShowId = UUID()
        scripts.setScript("Mine", forShowId: showId)
        scripts.setScript("Theirs", forShowId: otherShowId)
        scripts.deleteAll(forShowId: showId, extraScriptIds: [otherShowId])
        #expect(!scripts.hasScript(forShowId: showId))
        #expect(scripts.script(forShowId: otherShowId) == "Theirs")
    }

    @Test func addPrompterFillsFirstSlotThenExtras() throws {
        let store = try makeStore()
        let show = try store.create(name: "Talk", orientation: .landscape)
        let first = try #require(store.addPrompter(toShowId: show.id))
        #expect(first.token == ShowToolToken.prompter)
        #expect(first.scriptId == show.id)
        let second = try #require(store.addPrompter(toShowId: show.id))
        #expect(ShowToolToken.isExtraPrompterScriptId(second.scriptId))
        #expect(second.token == ShowToolToken.extraPrompterToken(scriptId: second.scriptId))
        let album = try #require(store.album(id: show.id))
        #expect(Array(album.resolvedSurfaceIds.suffix(2)) == [first.token, second.token])
    }

    @Test func extraPrompterListedByTwoShowsIsFlagged() throws {
        let store = try makeStore()
        let a = try store.create(name: "A", orientation: .landscape)
        let b = try store.create(name: "B", orientation: .landscape)
        let added = try #require(store.addPrompter(toShowId: a.id, reuseKeptScript: false))
        let extra = try #require(store.addPrompter(toShowId: a.id))
        #expect(added.scriptId == a.id)
        #expect(!store.isExtraPrompterListedElsewhere(extra.scriptId, showId: a.id))
        store.showTool(extra.token, albumId: b.id)
        #expect(store.isExtraPrompterListedElsewhere(extra.scriptId, showId: a.id))
        #expect(store.isExtraPrompterListedElsewhere(extra.scriptId, showId: b.id))
        #expect(store.isForeignPrompterScript(extra.scriptId, showId: b.id))
        #expect(!store.isForeignPrompterScript(a.id, showId: a.id))
    }
}
