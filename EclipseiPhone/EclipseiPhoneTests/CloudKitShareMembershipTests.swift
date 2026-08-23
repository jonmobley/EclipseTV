//
//  CloudKitShareMembershipTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CloudKitShareMembershipTests {

    @Test func unsharedShowKeepsFieldWithoutParent() {
        let showId = UUID()
        let resolved = CloudKitShareMembership.resolve(
            preferredShowId: showId,
            containingShowIds: [showId],
            shareRootIds: []
        )
        #expect(resolved.showId == showId)
        #expect(resolved.attachAsShareChild == false)
    }

    @Test func shareRootAttachesParent() {
        let showId = UUID()
        let resolved = CloudKitShareMembership.resolve(
            preferredShowId: showId,
            containingShowIds: [showId],
            shareRootIds: [showId]
        )
        #expect(resolved.showId == showId)
        #expect(resolved.attachAsShareChild == true)
    }

    @Test func prefersContainingShareRootOverUnsharedPreferred() {
        let preferred = UUID()
        let shared = UUID()
        let resolved = CloudKitShareMembership.resolve(
            preferredShowId: preferred,
            containingShowIds: [preferred, shared],
            shareRootIds: [shared]
        )
        #expect(resolved.showId == shared)
        #expect(resolved.attachAsShareChild == true)
    }

    @Test func emptyMembershipHasNoShow() {
        let resolved = CloudKitShareMembership.resolve(
            preferredShowId: nil,
            containingShowIds: [],
            shareRootIds: [UUID()]
        )
        #expect(resolved.showId == nil)
        #expect(resolved.attachAsShareChild == false)
    }
}

@MainActor
struct CloudKitShareRootStoreTests {

    @Test func markPersistsAcrossReload() throws {
        let suite = "CloudKitShareRootStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let id = UUID()

        let store = CloudKitShareRootStore(defaults: defaults, key: suite)
        #expect(store.mark(id) == true)
        #expect(store.mark(id) == false)

        let reloaded = CloudKitShareRootStore(defaults: defaults, key: suite)
        #expect(reloaded.contains(id))
        #expect(reloaded.unmark(id) == true)
        #expect(reloaded.contains(id) == false)
    }
}
