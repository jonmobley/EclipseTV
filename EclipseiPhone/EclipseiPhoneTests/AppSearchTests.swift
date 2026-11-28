//
//  AppSearchTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct AppSearchTests {

    private let showId = UUID()

    private var catalog: AppSearchCatalog {
        var catalog = AppSearchCatalog()
        catalog.shows = [
            (id: showId, entry: AppSearchEntry(title: "Sunday Service", symbolName: "s")),
            (id: UUID(), entry: AppSearchEntry(title: "Youth Night", symbolName: "s")),
        ]
        catalog.thisShow = [AppSearchEntry(title: "Welcome Café", symbolName: "c")]
        catalog.library = [
            AppSearchEntry(title: "Intro", keywords: ["sunday_intro.mp4"], symbolName: "v"),
        ]
        catalog.music = [AppSearchEntry(title: "Walk In", symbolName: "m")]
        return catalog
    }

    @Test func blankQueryFindsNothing() {
        #expect(AppSearch.results(for: "  ", in: catalog).isEmpty)
    }

    @Test func findsAcrossSectionsInOrder() {
        let groups = AppSearch.results(for: "sunday", in: catalog)
        #expect(groups.map(\.section) == [.shows, .library])
        #expect(groups[0].results.first?.target == .show(showId))
        // Found by its file name, listed by its title.
        #expect(groups[1].results.first?.title == "Intro")
        #expect(groups[1].results.first?.target == .page(.library))
    }

    @Test func ignoresCaseAndAccents() {
        let groups = AppSearch.results(for: "CAFE", in: catalog)
        #expect(groups.map(\.section) == [.thisShow])
        #expect(groups[0].results.first?.target == .page(.show))
    }

    @Test func musicGoesToTheMusicPage() {
        let groups = AppSearch.results(for: "walk", in: catalog)
        #expect(groups.first?.results.first?.target == .page(.music))
    }

    @Test func capsEachSection() {
        var big = AppSearchCatalog()
        big.music = (0..<100).map { AppSearchEntry(title: "Song \($0)", symbolName: "m") }
        let groups = AppSearch.results(for: "song", in: big)
        #expect(groups.first?.results.count == AppSearch.maxResultsPerSection)
    }
}
