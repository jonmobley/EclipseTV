//
//  HomeGridItemTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

@MainActor
struct HomeGridItemTests {

    @Test func hasBothOrientationsRequiresOneOfEach() {
        let landscape = LocalAlbum(name: "Wide", orientation: .landscape)
        let vertical = LocalAlbum(name: "Tall", orientation: .portrait)
        #expect(!HomeGridItem.hasBothOrientations(in: []))
        #expect(!HomeGridItem.hasBothOrientations(in: [landscape]))
        #expect(!HomeGridItem.hasBothOrientations(in: [vertical, vertical]))
        #expect(HomeGridItem.hasBothOrientations(in: [landscape, vertical]))
    }

    @Test func recentShowsUsesCreateShowWhenEmpty() {
        #expect(HomeGridItem.recentShows(from: []) == [.createShow])
    }

    @Test func recentShowsKeepsMixedOrderUntilFiltered() {
        let albums = [
            LocalAlbum(name: "A", orientation: .landscape),
            LocalAlbum(name: "B", orientation: .portrait),
            LocalAlbum(name: "C", orientation: .landscape)
        ]
        let mixed = HomeGridItem.recentShows(from: albums)
        #expect(names(in: mixed) == ["A", "B", "C"])

        let landscape = HomeGridItem.recentShows(from: albums, orientation: .landscape)
        #expect(names(in: landscape) == ["A", "C"])

        let vertical = HomeGridItem.recentShows(from: albums, orientation: .portrait)
        #expect(names(in: vertical) == ["B"])
    }

    @Test func recentShowsFilterThatMatchesNothingIsEmpty() {
        let albums = [LocalAlbum(name: "Wide", orientation: .landscape)]
        #expect(HomeGridItem.recentShows(from: albums, orientation: .portrait).isEmpty)
    }

    @Test func recentShowsRespectsHomeLimitAfterFilter() {
        let landscape = LocalAlbum(name: "Wide", orientation: .landscape)
        let vertical = (0..<8).map { index in
            LocalAlbum(name: "V\(index)", orientation: .portrait)
        }
        let filtered = HomeGridItem.recentShows(
            from: [landscape] + vertical,
            orientation: .portrait
        )
        #expect(filtered.count == HomeGridItem.recentHomeLimit)
        #expect(names(in: filtered) == ["V0", "V1", "V2", "V3", "V4", "V5"])
    }

    private func names(in items: [HomeGridItem]) -> [String] {
        items.compactMap { item in
            if case .show(let album) = item { return album.name }
            return nil
        }
    }
}
