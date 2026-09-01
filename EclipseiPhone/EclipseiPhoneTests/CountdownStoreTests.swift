//
//  CountdownStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CountdownStoreTests {

    private static let suiteName = "EclipseTV.CountdownStoreTests"

    @Test func nextDefaultNameIncrements() {
        let store = makeStore()
        let showId = UUID()
        #expect(store.nextDefaultName(inShowId: showId) == "Countdown")

        store.applyRemote(ShowCountdown(
            showId: showId, name: "Countdown", duration: 60
        ))
        #expect(store.nextDefaultName(inShowId: showId) == "Countdown 2")

        store.applyRemote(ShowCountdown(
            showId: showId, name: "Countdown 2", duration: 60
        ))
        #expect(store.nextDefaultName(inShowId: showId) == "Countdown 3")
    }

    @Test func tileTitleIncludesNameAndDuration() {
        let item = ShowCountdown(
            showId: UUID(), name: "Break", duration: 90
        )
        #expect(item.tileTitle() == "Break\n1:30")
        #expect(item.tileTitle(remaining: 5) == "Break\n0:05")
    }

    // MARK: - Helpers

    private func makeStore() -> CountdownStore {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.removePersistentDomain(forName: Self.suiteName)
        return CountdownStore(defaults: defaults)
    }
}
