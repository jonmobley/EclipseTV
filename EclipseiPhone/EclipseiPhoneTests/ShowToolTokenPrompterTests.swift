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

    private func makeScripts() throws -> PrompterScriptStore {
        let suite = "PrompterScripts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return PrompterScriptStore(defaults: defaults)
    }

    @Test func extraPrompterTokensResolvePerShow() throws {
        let showId = UUID()
        let otherShowId = UUID()
        let extra = ShowToolToken.newExtraPrompterToken()
        #expect(extra.hasPrefix(ShowToolToken.prefix))
        #expect(ShowToolToken.isTool(extra))
        #expect(ShowToolToken.isPrompter(extra))
        #expect(ShowToolToken.isPrompter(ShowToolToken.prompter))
        #expect(!ShowToolToken.isPrompter(ShowToolToken.camera))
        #expect(!ShowToolToken.isPrompter(ShowToolToken.extraPrompterPrefix + "nope"))
        #expect(ShowToolToken.prompterScriptId(from: ShowToolToken.prompter, showId: showId) == showId)
        let here = try #require(ShowToolToken.prompterScriptId(from: extra, showId: showId))
        let there = try #require(ShowToolToken.prompterScriptId(from: extra, showId: otherShowId))
        // Same token, different Show: a different script, so it can't reach this one.
        #expect(here != there)
        #expect(ShowToolToken.prompterScriptId(from: extra, showId: showId) == here)
        #expect(ShowToolToken.isExtraPrompterScriptId(here))
        #expect(
            ShowToolToken.prompterScriptIds(
                in: [ShowToolToken.camera, ShowToolToken.prompter, "a.jpg", extra], showId: showId
            ) == [showId, here]
        )
    }

    @Test func extraPrompterNeverNamesAShowsScript() {
        // Even a token whose nonce is a Show id derives an extra-shaped id, never a Show's.
        for _ in 0..<50 {
            let showId = UUID()
            let target = UUID()
            #expect(!ShowToolToken.isExtraPrompterScriptId(target))
            let planted = ShowToolToken.extraPrompterPrefix + target.uuidString
            let resolved = ShowToolToken.prompterScriptId(from: planted, showId: showId)
            #expect(resolved != target)
            #expect(resolved != showId)
        }
    }

    @Test func showHoldsSeveralPrompters() throws {
        let store = try makeStore()
        let show = try store.create(name: "Talk", orientation: .landscape)
        let first = try #require(store.addPrompter(toShowId: show.id))
        #expect(first.token == ShowToolToken.prompter)
        #expect(first.scriptId == show.id)
        let second = try #require(store.addPrompter(toShowId: show.id))
        #expect(second.token != first.token)
        #expect(ShowToolToken.prompterScriptId(from: second.token, showId: show.id) == second.scriptId)
        var album = try #require(store.album(id: show.id))
        #expect(Array(album.resolvedSurfaceIds.suffix(2)) == [first.token, second.token])

        store.hideTool(second.token, albumId: show.id)
        album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.contains(ShowToolToken.prompter))
        #expect(!album.resolvedSurfaceIds.contains(second.token))
    }

    @Test func sanitizedSurfaceKeepsExtraPrompterTokens() {
        let extra = ShowToolToken.newExtraPrompterToken()
        let surface = [ShowToolToken.prompter, extra, "photo.jpg"]
        #expect(LocalAlbum.sanitizedSurface(surface, itemIds: ["photo.jpg"]) == surface)
    }

    @Test func liveProgramLightsOnlyThePrompterOnScreen() {
        let showId = UUID()
        let extraToken = ShowToolToken.newExtraPrompterToken()
        let extraId = ShowToolToken.prompterScriptId(from: extraToken, showId: showId)!
        let first = ShowGridItem.prompter(token: ShowToolToken.prompter, scriptId: showId)
        let second = ShowGridItem.prompter(token: extraToken, scriptId: extraId)
        let program = ShowProgram(kind: .prompter, itemId: extraId.uuidString)
        #expect(program.matches(second))
        #expect(!program.matches(first))
        // An older director sends no id: both read as live rather than neither.
        let legacy = ShowProgram(kind: .prompter)
        #expect(legacy.matches(first) && legacy.matches(second))
    }

    @Test func deletingAShowRemovesEveryPrompterScript() throws {
        let scripts = try makeScripts()
        let showId = UUID()
        let otherId = UUID()
        let extraId = ShowToolToken.prompterScriptId(
            from: ShowToolToken.newExtraPrompterToken(), showId: showId
        )!
        scripts.setScript("Opening", forShowId: showId)
        scripts.setScript("Keynote", forShowId: extraId)
        scripts.setScript("Other show", forShowId: otherId)
        scripts.deleteAll(forShowId: showId, extraScriptIds: [showId, extraId])
        #expect(!scripts.hasScript(forShowId: showId))
        #expect(!scripts.hasScript(forShowId: extraId))
        #expect(scripts.script(forShowId: otherId) == "Other show")
    }

    @Test func deleteAllNeverTouchesAShowShapedScript() throws {
        let scripts = try makeScripts()
        let showId = UUID()
        let otherShowId = UUID()
        scripts.setScript("Mine", forShowId: showId)
        scripts.setScript("Theirs", forShowId: otherShowId)
        scripts.deleteAll(forShowId: showId, extraScriptIds: [otherShowId])
        #expect(!scripts.hasScript(forShowId: showId))
        #expect(scripts.script(forShowId: otherShowId) == "Theirs")
    }

    @Test func tokenMovedToAnotherShowCannotReachTheOriginalScript() throws {
        let store = try makeStore()
        let a = try store.create(name: "A", orientation: .landscape)
        let b = try store.create(name: "B", orientation: .landscape)
        _ = store.addPrompter(toShowId: a.id)
        let extra = try #require(store.addPrompter(toShowId: a.id))
        // A removes the tile (its script is kept), then B lists the same token.
        store.hideTool(extra.token, albumId: a.id)
        store.showTool(extra.token, albumId: b.id)
        let onB = try #require(ShowToolToken.prompterScriptId(from: extra.token, showId: b.id))
        #expect(onB != extra.scriptId)
        let deletedWithB = ShowToolToken.prompterScriptIds(
            in: try #require(store.album(id: b.id)).resolvedSurfaceIds, showId: b.id
        )
        #expect(!deletedWithB.contains(extra.scriptId))
    }
}
