//
//  HomeContinueContentTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct HomeContinueContentTests {

    @Test func noShowsOffersTheFirstShow() {
        let content = LibraryGridViewController.homeContinueContent(albums: [], cover: { _ in nil })
        #expect(content == .firstShow)
    }

    @Test func continuesTheMostRecentShow() {
        let recent = LocalAlbum(
            name: "Sunday Service",
            itemIds: ["a.jpg", "b.jpg", "c.jpg"],
            lastOpenedAt: Date().addingTimeInterval(-3 * 3600)
        )
        let older = LocalAlbum(name: "Older")
        let content = LibraryGridViewController.homeContinueContent(
            albums: [recent, older], cover: { _ in nil }
        )
        guard case let .show(id, name, detail, _) = content else {
            Issue.record("Expected a Show")
            return
        }
        #expect(id == recent.id)
        #expect(name == "Sunday Service")
        #expect(detail.hasPrefix("Opened "))
        #expect(detail.hasSuffix("· 3 items"))
    }
}
