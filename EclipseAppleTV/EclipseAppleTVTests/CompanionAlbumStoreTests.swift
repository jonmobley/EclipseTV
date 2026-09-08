//
//  CompanionAlbumStoreTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseAppleTV

/// Main actor because `replaceAll` posts `didChangeNotification`, and the live
/// `ImageViewController` in the test host observes it and calls `reloadData()`.
/// On tvOS that reaches the focus engine, which aborts the process off the main
/// thread — Swift Testing runs bodies on background tasks, so these two tests
/// crashed the host whenever the app had already reached grid mode. That made it
/// look like a flake: the surviving simulator clone's pass is what the result
/// bundle recorded, while `xcodebuild` still failed the run.
///
/// This mirrors production rather than working around it. `ConnectionManager`
/// hops to `DispatchQueue.main` before `didReceiveLibraryAlbums`, so `replaceAll`
/// is only ever called on the main thread outside of tests.
@MainActor
struct CompanionAlbumStoreTests {

    @Test func displayAlbumsFilterByModeAndLiveIds() {
        let store = CompanionAlbumStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.replaceAll([
            LibraryAlbumDTO(
                id: "wedding",
                name: "Wedding",
                itemIds: ["a.jpg", "missing.jpg", "b.jpg"],
                coverId: "a.jpg",
                libraryMode: "landscape"
            ),
            LibraryAlbumDTO(
                id: "portrait",
                name: "Portrait",
                itemIds: ["c.jpg"],
                coverId: "c.jpg",
                libraryMode: "vertical"
            )
        ])

        let shown = store.displayAlbums(for: .landscape, liveIds: ["a.jpg", "b.jpg"])
        #expect(shown.count == 1)
        #expect(shown[0].id == "wedding")
        #expect(shown[0].itemIds == ["a.jpg", "b.jpg"])
    }

    @Test func leftoverIdsAreUnfiled() {
        let store = CompanionAlbumStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.replaceAll([
            LibraryAlbumDTO(
                id: "show",
                name: "Show",
                itemIds: ["keep.jpg"],
                coverId: "keep.jpg",
                libraryMode: "landscape"
            )
        ])

        let leftover = store.leftoverIds(
            liveIds: ["keep.jpg", "loose.jpg"],
            for: .landscape
        )
        #expect(leftover == ["loose.jpg"])
    }

    @Test func envelopeLibraryAlbumsRoundTrips() {
        let albums = [
            LibraryAlbumDTO(
                id: UUID().uuidString,
                name: "Rehearsal",
                itemIds: ["one.jpg"],
                coverId: "one.jpg",
                libraryMode: "landscape"
            )
        ]
        let data = EclipseShareEnvelope.setLibraryAlbums(albums).encoded()
        let decoded = EclipseShareEnvelope.decode(from: data!)
        #expect(decoded?.kind == .setLibraryAlbums)
        #expect(decoded?.albums == albums)
    }
}
