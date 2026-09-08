//
//  CloudKitPendingDeleteStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CloudKitPendingDeleteStoreTests {

    private func makeDefaults(_ suite: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A delete recorded while the engine was nil has to survive relaunch, or the
    /// next fetch re-inserts the object the user deleted.
    @Test func notedDeleteSurvivesReload() throws {
        let suite = "PendingDeletes.\(UUID().uuidString)"
        let defaults = try makeDefaults(suite)
        let store = CloudKitPendingDeleteStore(defaults: defaults, key: suite)

        store.note("show-1")
        let reloaded = CloudKitPendingDeleteStore(defaults: defaults, key: suite)

        #expect(reloaded.recordNames == ["show-1"])
    }

    @Test func clearRemovesOnlyThatRecord() throws {
        let suite = "PendingDeletes.\(UUID().uuidString)"
        let store = CloudKitPendingDeleteStore(
            defaults: try makeDefaults(suite), key: suite
        )

        store.note("a")
        store.note("b")
        store.clear("a")

        #expect(store.recordNames == ["b"])
    }

    /// A save must cancel a stale delete for the same id: the singleton Background
    /// and Screensaver records can be cleared and set again.
    @Test func repeatedNotesDoNotDuplicate() throws {
        let suite = "PendingDeletes.\(UUID().uuidString)"
        let store = CloudKitPendingDeleteStore(
            defaults: try makeDefaults(suite), key: suite
        )

        store.note("eclipse.background")
        store.note("eclipse.background")

        #expect(store.recordNames.count == 1)

        store.removeAll()
        #expect(store.recordNames.isEmpty)
    }
}
