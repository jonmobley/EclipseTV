//
//  LocalAlbumLivePreviewTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct LocalAlbumLivePreviewTests {

    @Test func newShowDefaultsPracticePreviewOff() {
        let album = LocalAlbum(name: "Rehearsal")
        #expect(album.previewsWhenDisconnected == false)
    }

    @Test func missingJSONKeyDecodesAsOff() throws {
        let album = LocalAlbum(name: "Legacy")
        let encoded = try JSONEncoder().encode(album)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "previewsWhenDisconnected")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LocalAlbum.self, from: stripped)
        #expect(decoded.previewsWhenDisconnected == false)
        #expect(decoded.name == "Legacy")
    }

    @Test func trueRoundTripsThroughJSON() throws {
        let album = LocalAlbum(name: "Practice", previewsWhenDisconnected: true)
        let data = try JSONEncoder().encode(album)
        let decoded = try JSONDecoder().decode(LocalAlbum.self, from: data)
        #expect(decoded.previewsWhenDisconnected == true)
        #expect(decoded.name == "Practice")
    }

    @Test func storePersistsPracticePreviewFlag() throws {
        let suite = "LocalAlbumLivePreviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalAlbumStore(defaults: defaults)
        let show = try store.create(name: "Stage", orientation: .landscape)
        #expect(show.previewsWhenDisconnected == false)

        store.setPreviewsWhenDisconnected(true, albumId: show.id)
        #expect(store.album(id: show.id)?.previewsWhenDisconnected == true)

        store.setPreviewsWhenDisconnected(false, albumId: show.id)
        #expect(store.album(id: show.id)?.previewsWhenDisconnected == false)
    }

    @Test func cloudKitRoundTripPreservesPracticePreview() throws {
        let album = LocalAlbum(name: "Shared", previewsWhenDisconnected: true)
        let record = CloudKitRecordMapper.makeShowRecord(from: album)
        #expect(
            record[CloudKitSchema.ShowKey.previewsWhenDisconnected] as? Bool == true
        )
        let decoded = try #require(CloudKitRecordMapper.album(from: record))
        #expect(decoded.previewsWhenDisconnected == true)
    }

    @Test func cloudKitMissingFieldDefaultsOff() throws {
        let album = LocalAlbum(name: "Old Record")
        let record = CloudKitRecordMapper.makeShowRecord(from: album)
        record[CloudKitSchema.ShowKey.previewsWhenDisconnected] = nil
        let decoded = try #require(CloudKitRecordMapper.album(from: record))
        #expect(decoded.previewsWhenDisconnected == false)
    }
}
