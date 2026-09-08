//
//  CloudKitShowDirtyStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CloudKitShowDirtyStoreTests {

    private func makeDefaults(_ suite: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Installs that predate dirty tracking must upload their Shows once, rather
    /// than being treated as fully synced and never enqueued again.
    @Test func firstRunSeedsEveryShowDirty() throws {
        let suite = "ShowDirty.\(UUID().uuidString)"
        let store = CloudKitShowDirtyStore(
            defaults: try makeDefaults(suite), key: suite
        )
        let a = UUID()
        let b = UUID()

        store.seedIfNeeded(with: [a, b])

        #expect(store.contains(a))
        #expect(store.contains(b))
    }

    /// Seeding is one-shot: once a Show is clean, a later seed must not resurrect it
    /// or every foreground would re-upload the whole Show list again.
    @Test func seedDoesNotResurrectCleanShows() throws {
        let suite = "ShowDirty.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        let store = CloudKitShowDirtyStore(defaults: defaults, key: suite)
        let id = UUID()

        store.seedIfNeeded(with: [id])
        store.markClean(id)
        store.seedIfNeeded(with: [id])

        #expect(store.contains(id) == false)

        let reloaded = CloudKitShowDirtyStore(defaults: defaults, key: suite)
        reloaded.seedIfNeeded(with: [id])
        #expect(reloaded.contains(id) == false)
    }

    @Test func localEditMarksDirtyAndPersists() throws {
        let suite = "ShowDirty.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        let store = CloudKitShowDirtyStore(defaults: defaults, key: suite)
        let id = UUID()

        store.seedIfNeeded(with: [])
        store.markDirty(id)

        let reloaded = CloudKitShowDirtyStore(defaults: defaults, key: suite)
        #expect(reloaded.contains(id))
    }

    @Test func markAllDirtyReplacesTheSet() throws {
        let suite = "ShowDirty.\(UUID().uuidString)"
        let store = CloudKitShowDirtyStore(
            defaults: try makeDefaults(suite), key: suite
        )
        let stale = UUID()
        let live = UUID()

        store.markDirty(stale)
        store.markAllDirty([live])

        #expect(store.contains(live))
        #expect(store.contains(stale) == false)
    }
}
