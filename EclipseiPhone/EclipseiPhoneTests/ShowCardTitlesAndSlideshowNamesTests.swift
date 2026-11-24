//
//  ShowCardTitlesAndSlideshowNamesTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

/// Settings → Card Titles (per Show, synced) and "Slideshow 01" default names.
@MainActor
struct ShowCardTitlesAndSlideshowNamesTests {

    // MARK: - Card Titles

    @Test func olderSavedShowsHaveTitlesOn() throws {
        let album = LocalAlbum(name: "Legacy", cardTitlesShown: false)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(album)) as? [String: Any]
        )
        object.removeValue(forKey: "cardTitlesShown")
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(LocalAlbum.self, from: data).cardTitlesShown == true)
    }

    @Test func cardTitlesSyncWithTheShowRecord() throws {
        let album = LocalAlbum(name: "Gala", cardTitlesShown: false)
        let record = CloudKitRecordMapper.makeShowRecord(from: album)
        #expect(record[CloudKitSchema.ShowKey.cardTitlesShown] as? Bool == false)
        #expect(try #require(CloudKitRecordMapper.album(from: record)).cardTitlesShown == false)
        record[CloudKitSchema.ShowKey.cardTitlesShown] = nil
        #expect(try #require(CloudKitRecordMapper.album(from: record)).cardTitlesShown == true)
    }

    @Test func storeSavesTheSetting() throws {
        let suite = "ShowCardTitles.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalAlbumStore(defaults: defaults)
        let show = try store.create(name: "Stage", orientation: .landscape)
        #expect(show.cardTitlesShown == true)
        store.setCardTitlesShown(false, albumId: show.id)
        #expect(store.album(id: show.id)?.cardTitlesShown == false)
    }

    // MARK: - Slideshow Names

    @Test func numberedNamesCountUp() {
        #expect(SlideshowNaming.nextName(existing: []) == "Slideshow 01")
        #expect(SlideshowNaming.nextName(existing: ["Slideshow 01", "Slideshow 7", "Walk-in"]) == "Slideshow 08")
        #expect(SlideshowNaming.nextName(existing: ["My Slideshow 05", "Slideshow 2B"]) == "Slideshow 01")
        #expect(SlideshowNaming.nextName(existing: ["Slideshow 9223372036854775807"]) == "Slideshow 01")
    }

    @Test func blankNamesBecomeNumbered() throws {
        let suite = "SlideshowNames.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SlideshowStore(defaults: defaults)
        let showId = UUID()
        let first = try store.create(name: "  ", showId: showId, itemIds: ["a", "b"])
        let second = try store.create(name: "", showId: showId, itemIds: ["c", "d"])
        #expect(first.name == "Slideshow 01")
        #expect(second.name == "Slideshow 02")
        try store.rename(id: first.id, to: "")
        #expect(store.slideshow(id: first.id)?.name == "Slideshow 03")
    }
}
