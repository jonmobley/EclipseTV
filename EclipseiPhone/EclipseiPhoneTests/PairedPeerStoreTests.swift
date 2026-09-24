//
//  PairedPeerStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct PairedPeerStoreTests {

    private func makeStore() throws -> (PairedPeerStore, UserDefaults) {
        let suite = "PairedPeerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (PairedPeerStore(defaults: defaults), defaults)
    }

    @Test func rememberAndForgetRoundTrip() throws {
        let (store, _) = try makeStore()
        store.remember(displayName: "Living Room")
        #expect(store.isPaired(displayName: "Living Room"))
        store.forget(displayName: "Living Room")
        #expect(!store.isPaired(displayName: "Living Room"))
    }

    @Test func unreadablePayloadBlocksOverwrite() throws {
        let (store, defaults) = try makeStore()
        let key = "EclipseTV.companion.pairedTVs"
        let raw = try #require("{not json".data(using: .utf8))
        defaults.set(raw, forKey: key)

        #expect(!store.isPaired(displayName: "X"))
        store.remember(displayName: "X")
        #expect(!store.isPaired(displayName: "X"))
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == raw)
    }

    @Test func forgetAllClearsBackup() throws {
        let (store, defaults) = try makeStore()
        let key = "EclipseTV.companion.pairedTVs"
        defaults.set(try #require("{bad".data(using: .utf8)), forKey: key)
        _ = store.allPairedNames()
        store.forgetAll()
        #expect(defaults.data(forKey: key) == nil)
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == nil)
        store.remember(displayName: "Fresh")
        #expect(store.isPaired(displayName: "Fresh"))
    }
}
