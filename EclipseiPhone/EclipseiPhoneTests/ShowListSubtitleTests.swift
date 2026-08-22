//
//  ShowListSubtitleTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowListSubtitleTests {

    @Test func listAndTileCaptionsAreRecencyOnly() {
        let hoursAgo = Date().addingTimeInterval(-6 * 3600)
        let vertical = LocalAlbum(
            name: "Tall",
            orientation: .portrait,
            lastOpenedAt: hoursAgo
        )
        let landscape = LocalAlbum(
            name: "Wide",
            orientation: .landscape,
            lastOpenedAt: hoursAgo
        )

        for album in [vertical, landscape] {
            #expect(album.showListSubtitle == album.lastOpenedSubtitle)
            #expect(album.homeRecentSubtitle == album.lastOpenedSubtitle)
            #expect(!album.showListSubtitle.contains("Vertical"))
            #expect(!album.showListSubtitle.contains("Landscape"))
            #expect(!album.homeRecentSubtitle.contains("Vertical"))
            #expect(!album.homeRecentSubtitle.contains("Landscape"))
        }
    }

    @Test func compactRelativeOpenStringUsesShortHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 18, hour: 18)
        )!
        let sixHoursEarlier = now.addingTimeInterval(-6 * 3600)
        #expect(
            LocalAlbum.compactRelativeOpenString(
                for: sixHoursEarlier,
                now: now,
                calendar: calendar
            ) == "6hrs ago"
        )
    }

    @Test func pickerGlyphDiffersByOrientation() {
        let vertical = LocalAlbum(name: "Tall", orientation: .portrait)
        let landscape = LocalAlbum(name: "Wide", orientation: .landscape)
        #expect(vertical.showPickerIconName != landscape.showPickerIconName)
        #expect(vertical.showPickerIconName.contains("portrait"))
        #expect(!landscape.showPickerIconName.contains("portrait"))
    }
}
