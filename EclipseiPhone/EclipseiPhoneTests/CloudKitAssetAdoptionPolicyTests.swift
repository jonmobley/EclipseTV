//
//  CloudKitAssetAdoptionPolicyTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CloudKitAssetAdoptionPolicyTests {

    private let staged = URL(fileURLWithPath: "/tmp/staged-asset.mov")

    @Test func keepsBytesForAnItemThisDeviceDoesNotHave() {
        #expect(
            CloudKitAssetAdoptionPolicy.adoptableURL(
                staged,
                hasLocalBytes: false,
                wasEvictedByUser: false
            ) == staged
        )
    }

    @Test func skipsWhenTheFileIsAlreadyOnDisk() {
        #expect(
            CloudKitAssetAdoptionPolicy.adoptableURL(
                staged,
                hasLocalBytes: true,
                wasEvictedByUser: false
            ) == nil
        )
    }

    /// The whole point of the eviction index: a metadata edit made anywhere must not
    /// silently restore a download the user deleted to reclaim space.
    @Test func skipsWhenTheUserRemovedTheDownload() {
        #expect(
            CloudKitAssetAdoptionPolicy.adoptableURL(
                staged,
                hasLocalBytes: false,
                wasEvictedByUser: true
            ) == nil
        )
    }

    @Test func skipsWhenNoAssetRodeAlong() {
        #expect(
            CloudKitAssetAdoptionPolicy.adoptableURL(
                nil,
                hasLocalBytes: false,
                wasEvictedByUser: false
            ) == nil
        )
    }
}

@MainActor
struct CloudKitEvictedMediaStoreTests {

    private let key = "EclipseTV.cloudKit.evictedMedia"

    private func makeDefaults() throws -> UserDefaults {
        let suite = "CloudKitEvictedMediaStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults) -> CloudKitEvictedMediaStore {
        CloudKitEvictedMediaStore(defaults: defaults, key: key)
    }

    @Test func notesAndClearsAnEviction() throws {
        let store = makeStore(try makeDefaults())
        store.note("media-1")

        #expect(store.contains("media-1"))

        store.clear("media-1")

        #expect(!store.contains("media-1"))
    }

    /// Evictions have to outlive a launch, or the next cold sync re-downloads
    /// everything the user just cleared.
    @Test func evictionsSurviveReload() throws {
        let defaults = try makeDefaults()
        makeStore(defaults).note("media-1")

        #expect(makeStore(defaults).contains("media-1"))
    }

    @Test func untrackedIdsAreNotEvicted() throws {
        let store = makeStore(try makeDefaults())
        store.note("media-1")

        #expect(!store.contains("media-2"))
    }

    @Test func removeAllClearsEveryEviction() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        store.note("media-1")
        store.note("media-2")
        store.removeAll()

        #expect(!store.contains("media-1"))
        #expect(!makeStore(defaults).contains("media-2"))
    }
}
