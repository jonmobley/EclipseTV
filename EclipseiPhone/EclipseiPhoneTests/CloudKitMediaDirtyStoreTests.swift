//
//  CloudKitMediaDirtyStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CloudKitMediaDirtyStoreTests {

    private let key = "EclipseTV.cloudKit.mediaNeedingUpload"

    private func makeDefaults() throws -> UserDefaults {
        let suite = "CloudKitMediaDirtyStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults) -> CloudKitMediaDirtyStore {
        CloudKitMediaDirtyStore(defaults: defaults, key: key)
    }

    @Test func marksDirtyAndClean() throws {
        let store = makeStore(try makeDefaults())
        store.markDirty("media-1")

        #expect(store.contains("media-1"))

        store.markClean("media-1")

        #expect(!store.contains("media-1"))
    }

    @Test func dirtyIdsSurviveReload() throws {
        let defaults = try makeDefaults()
        makeStore(defaults).markDirty("media-1")

        #expect(makeStore(defaults).contains("media-1"))
    }

    /// The seed exists for installs that predate dirty tracking, whose preference
    /// edits used to travel on the blanket re-enqueue.
    @Test func seedRunsOnceThenLeavesTheSetAlone() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        store.seedIfNeeded(with: ["media-1", "media-2"])

        #expect(Set(store.allDirty) == ["media-1", "media-2"])

        store.markClean("media-1")
        store.seedIfNeeded(with: ["media-1", "media-2"])

        #expect(Set(store.allDirty) == ["media-2"])
    }

    /// A reload must not re-seed: the stored set, empty or not, is the truth.
    @Test func seedDoesNotRunAgainAfterReload() throws {
        let defaults = try makeDefaults()
        let first = makeStore(defaults)
        first.seedIfNeeded(with: ["media-1"])
        first.markClean("media-1")

        let reloaded = makeStore(defaults)
        reloaded.seedIfNeeded(with: ["media-1"])

        #expect(reloaded.allDirty.isEmpty)
    }

    @Test func markAllDirtyReplacesTheSet() throws {
        let store = makeStore(try makeDefaults())
        store.markDirty("stale-1")
        store.markAllDirty(["media-1", "media-2"])

        #expect(Set(store.allDirty) == ["media-1", "media-2"])
    }

    @Test func removeAllClearsTracking() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        store.markAllDirty(["media-1", "media-2"])
        store.removeAll()

        #expect(store.allDirty.isEmpty)
        #expect(makeStore(defaults).allDirty.isEmpty)
    }
}
