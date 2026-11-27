//
//  PendingTVDeleteStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
import UIKit
@testable import EclipseiPhone

/// Library deletes made with no EclipseTV linked are remembered until the TV drops them.
@MainActor
struct PendingTVDeleteStoreTests {

    private func makeStore() -> (PendingTVDeleteStore, UserDefaults) {
        let suite = "PendingTVDeleteStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return (PendingTVDeleteStore(defaults: defaults, defaultsKey: "deletes"), defaults)
    }

    @Test func remembersDeletesPerMode() {
        let (store, _) = makeStore()
        store.add("a", mode: .landscape)
        store.add("b", mode: .vertical)
        #expect(store.contains("a"))
        #expect(store.ids(for: .landscape) == ["a"])
        #expect(store.ids(for: .vertical) == ["b"])
    }

    @Test func keepsIdsTheTVStillListsAndForgetsTheRest() {
        let (store, _) = makeStore()
        store.add("still-there", mode: .landscape)
        store.add("gone", mode: .landscape)
        let resend = store.reconcile(manifestIds: ["still-there", "other"], mode: .landscape)
        #expect(resend == ["still-there"])
        #expect(store.contains("still-there"))
        #expect(!store.contains("gone"))
    }

    @Test func otherModesManifestLeavesIdsAlone() {
        let (store, _) = makeStore()
        store.add("v", mode: .vertical)
        store.reconcile(manifestIds: [], mode: .landscape)
        #expect(store.contains("v"))
    }

    @Test func survivesRelaunch() {
        let (store, defaults) = makeStore()
        store.add("a", mode: .landscape)
        let reloaded = PendingTVDeleteStore(defaults: defaults, defaultsKey: "deletes")
        #expect(reloaded.contains("a"))
    }

    @Test func deleteMessageSaysWhenTheTVCopyGoes() {
        #expect(UIViewController.libraryDeleteMessage(isPending: true, isLinked: false)
                == "This removes the item you added.")
        #expect(UIViewController.libraryDeleteMessage(isPending: false, isLinked: true)
                == "This removes the item from your Apple TV library.")
        #expect(UIViewController.libraryDeleteMessage(isPending: false, isLinked: false)
                .contains("next time it's linked"))
    }
}
