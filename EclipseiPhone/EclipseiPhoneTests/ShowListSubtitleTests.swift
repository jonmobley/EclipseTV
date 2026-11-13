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

    @Test func captionNamesTheEventItMeasures() {
        let opened = LocalAlbum(
            name: "Opened",
            orientation: .landscape,
            lastOpenedAt: Date().addingTimeInterval(-6 * 3600)
        )
        #expect(opened.lastOpenedSubtitle.hasPrefix("Opened "))

        let neverOpened = LocalAlbum(name: "Synced", orientation: .landscape)
        #expect(neverOpened.lastOpenedSubtitle.hasPrefix("Created "))
    }

    @Test func eventCaptionLowercasesWordyTimes() {
        #expect(LocalAlbum.eventSubtitle("Opened", "Just now") == "Opened just now")
        #expect(LocalAlbum.eventSubtitle("Opened", "Yesterday") == "Opened yesterday")
        #expect(LocalAlbum.eventSubtitle("Created", "2 months ago") == "Created 2 months ago")
    }

    @Test func syncKeepsTheLaterOpenTime() {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        #expect(LocalAlbum.latest(later, nil) == later)
        #expect(LocalAlbum.latest(nil, earlier) == earlier)
        #expect(LocalAlbum.latest(earlier, later) == later)
        #expect(LocalAlbum.latest(nil, nil) == nil)
    }

    @Test func pickerGlyphDiffersByOrientation() {
        let vertical = LocalAlbum(name: "Tall", orientation: .portrait)
        let landscape = LocalAlbum(name: "Wide", orientation: .landscape)
        #expect(vertical.showPickerIconName != landscape.showPickerIconName)
        #expect(vertical.showPickerIconName.contains("portrait"))
        #expect(!landscape.showPickerIconName.contains("portrait"))
    }
}
