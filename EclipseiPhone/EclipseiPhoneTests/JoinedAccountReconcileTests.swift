//
//  JoinedAccountReconcileTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseiPhone

struct JoinedAccountReconcileTests {

    @Test func emptyBothIsNone() {
        #expect(JoinedAccountReconcile.outcome(phone: nil, tv: nil) == .none)
    }

    @Test func phoneAdoptsTVWhenEmpty() {
        #expect(
            JoinedAccountReconcile.outcome(phone: nil, tv: "12 34 56") == .adoptTV("123456")
        )
    }

    @Test func phonePushesWhenTVEmpty() {
        #expect(
            JoinedAccountReconcile.outcome(phone: "654321", tv: nil) == .pushPhone("654321")
        )
    }

    @Test func matchingCodesAreNone() {
        #expect(
            JoinedAccountReconcile.outcome(phone: "111222", tv: "111222") == .none
        )
    }

    @Test func differingCodesConflict() {
        #expect(
            JoinedAccountReconcile.outcome(phone: "111222", tv: "333444")
                == .conflict(phone: "111222", tv: "333444")
        )
    }

    @Test func envelopeLibraryAlbumsRoundTrips() {
        let albums = [
            LibraryAlbumDTO(
                id: "show-1",
                name: "Dinner",
                itemIds: ["plate.jpg"],
                coverId: "plate.jpg",
                libraryMode: "vertical"
            )
        ]
        let data = EclipseShareEnvelope.setLibraryAlbums(albums).encoded()
        let decoded = EclipseShareEnvelope.decode(from: data!)
        #expect(decoded?.kind == .setLibraryAlbums)
        #expect(decoded?.albums == albums)
    }
}
