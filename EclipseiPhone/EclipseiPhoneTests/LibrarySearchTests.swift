//
//  LibrarySearchTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct LibrarySearchTests {

    @Test func blankQueryMatchesEverything() {
        #expect(LibrarySearch.matches("", in: [nil]))
        #expect(LibrarySearch.matches("   ", in: ["Welcome"]))
        #expect(LibrarySearch.matches("", in: ["Opening hymn"]))
    }

    @Test func matchesOverlayTitle() {
        #expect(LibrarySearch.matches("hymn", in: ["Opening hymn", "IMG_1000.JPG"]))
        #expect(!LibrarySearch.matches("hymn", in: ["Welcome", "IMG_1000.JPG"]))
    }

    @Test func matchesFilenameWhenUntitled() {
        #expect(LibrarySearch.matches("IMG_1000", in: [nil, "IMG_1000.JPG"]))
        #expect(!LibrarySearch.matches("hymn", in: [nil, "IMG_1000.JPG"]))
    }

    @Test func matchesPDFTitle() {
        #expect(LibrarySearch.matches("bulletin", in: ["Sunday Bulletin"]))
        #expect(!LibrarySearch.matches("hymn", in: ["Sunday Bulletin"]))
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(LibrarySearch.matches("cafe", in: ["Café"]))
        #expect(LibrarySearch.matches("WELCOME", in: ["Welcome slide"]))
    }
}
