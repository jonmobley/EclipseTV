//
//  PrompterScriptStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct PrompterScriptStoreTests {

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
        func tick() -> Date { now += 1; return now }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "PrompterScript.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(
        defaults: UserDefaults? = nil,
        clock: Clock = Clock()
    ) throws -> PrompterScriptStore {
        PrompterScriptStore(defaults: try defaults ?? makeDefaults(), now: { clock.now })
    }

    @Test func emptyByDefault() throws {
        let store = try makeStore()
        let showId = UUID()
        #expect(store.entry(forShowId: showId) == nil)
        #expect(store.script(forShowId: showId) == "")
        #expect(!store.hasScript(forShowId: showId))
        #expect(store.idsNeedingUpload.isEmpty)
    }

    @Test func setScriptStampsClockAndPostsNotification() throws {
        let clock = Clock()
        let store = try makeStore(clock: clock)
        let showId = UUID()
        var posted: [UUID] = []
        let token = NotificationCenter.default.addObserver(
            forName: PrompterScriptStore.didChangeNotification,
            object: nil,
            queue: nil
        ) { note in
            if let id = note.object as? UUID { posted.append(id) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.setScript("Good evening.", forShowId: showId)
        let entry = try #require(store.entry(forShowId: showId))
        #expect(entry.script == "Good evening.")
        #expect(entry.modifiedAt == clock.now)
        #expect(posted == [showId])
        #expect(store.idsNeedingUpload == [showId])
    }

    @Test func unchangedScriptIsIgnored() throws {
        let clock = Clock()
        let store = try makeStore(clock: clock)
        let showId = UUID()
        store.setScript("Same", forShowId: showId)
        let first = try #require(store.entry(forShowId: showId))
        _ = clock.tick()
        store.setScript("Same", forShowId: showId)
        #expect(store.entry(forShowId: showId) == first)
    }

    @Test func clearingKeepsAnEmptyEntrySoTheClearSyncs() throws {
        let store = try makeStore()
        let showId = UUID()
        store.setScript("Draft", forShowId: showId)
        store.markSynced(showId: showId)
        store.setScript("", forShowId: showId)
        let entry = try #require(store.entry(forShowId: showId))
        #expect(entry.script == "")
        #expect(store.idsNeedingUpload == [showId])
    }

    @Test func clearingAShowThatNeverHadAScriptIsANoOp() throws {
        let store = try makeStore()
        let showId = UUID()
        store.setScript("", forShowId: showId)
        #expect(store.entry(forShowId: showId) == nil)
        #expect(store.idsNeedingUpload.isEmpty)
    }

    @Test func remoteNewerReplacesLocalAndMarksSynced() throws {
        let clock = Clock()
        let store = try makeStore(clock: clock)
        let showId = UUID()
        store.setScript("Local", forShowId: showId)
        let incoming = PrompterScript(
            showId: showId, script: "Remote", modifiedAt: clock.tick()
        )
        #expect(store.applyRemote(incoming))
        #expect(store.script(forShowId: showId) == "Remote")
        #expect(store.idsNeedingUpload.isEmpty)
    }

    @Test func remoteOlderIsIgnoredAndLocalStaysDirty() throws {
        let clock = Clock()
        let store = try makeStore(clock: clock)
        let showId = UUID()
        let older = clock.now.addingTimeInterval(-10)
        store.setScript("Local", forShowId: showId)
        let incoming = PrompterScript(showId: showId, script: "Remote", modifiedAt: older)
        #expect(!store.applyRemote(incoming))
        #expect(store.script(forShowId: showId) == "Local")
        #expect(store.idsNeedingUpload == [showId])
    }

    @Test func tieGoesToRemote() throws {
        let clock = Clock()
        let store = try makeStore(clock: clock)
        let showId = UUID()
        store.setScript("Local", forShowId: showId)
        let incoming = PrompterScript(showId: showId, script: "Remote", modifiedAt: clock.now)
        #expect(store.applyRemote(incoming))
        #expect(store.script(forShowId: showId) == "Remote")
    }

    @Test func remoteForUnknownShowIsStored() throws {
        let store = try makeStore()
        let showId = UUID()
        let incoming = PrompterScript(showId: showId, script: "Early", modifiedAt: Date())
        #expect(store.applyRemote(incoming))
        #expect(store.script(forShowId: showId) == "Early")
        #expect(store.idsNeedingUpload.isEmpty)
    }

    @Test func scriptIsClampedToMaxLength() throws {
        let store = try makeStore()
        let showId = UUID()
        let long = String(repeating: "x", count: PrompterScriptStore.maxScriptLength + 5)
        store.setScript(long, forShowId: showId)
        #expect(store.script(forShowId: showId).count == PrompterScriptStore.maxScriptLength)
    }

    @Test func deleteAllForShowRemovesEntryAndSyncFlag() throws {
        let store = try makeStore()
        let showId = UUID()
        store.setScript("Bye", forShowId: showId)
        store.markSynced(showId: showId)
        store.deleteAll(forShowId: showId)
        #expect(store.entry(forShowId: showId) == nil)
        #expect(store.idsNeedingUpload.isEmpty)
    }

    @Test func purgeRemoteDropsTheEntry() throws {
        let store = try makeStore()
        let showId = UUID()
        store.setScript("Gone", forShowId: showId)
        store.purgeRemote(showId: showId)
        #expect(store.entry(forShowId: showId) == nil)
    }

    @Test func markAllNeedsUploadReflagsEverything() throws {
        let store = try makeStore()
        let a = UUID()
        let b = UUID()
        store.setScript("A", forShowId: a)
        store.setScript("B", forShowId: b)
        store.markSynced(showId: a)
        store.markSynced(showId: b)
        #expect(store.idsNeedingUpload.isEmpty)
        store.markAllNeedsUpload()
        #expect(Set(store.idsNeedingUpload) == [a, b])
    }

    @Test func entriesPersistAcrossReload() throws {
        let defaults = try makeDefaults()
        let showId = UUID()
        do {
            let store = try makeStore(defaults: defaults)
            store.setScript("Kept", forShowId: showId)
            store.markSynced(showId: showId)
        }
        let reloaded = try makeStore(defaults: defaults)
        #expect(reloaded.script(forShowId: showId) == "Kept")
        #expect(reloaded.idsNeedingUpload.isEmpty)
    }
}
