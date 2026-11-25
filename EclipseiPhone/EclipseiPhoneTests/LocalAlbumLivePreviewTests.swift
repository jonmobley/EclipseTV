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

/// Practice Mode used to be a per-Show switch stored as `previewsWhenDisconnected`.
/// It is always on now (2026-11-25), but builds before that still read the key as
/// their switch, so every save must keep telling them "on".
@MainActor
struct LocalAlbumLivePreviewTests {

    @Test func savedShowTellsOlderBuildsPracticeIsOn() throws {
        let data = try JSONEncoder().encode(LocalAlbum(name: "Rehearsal"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["previewsWhenDisconnected"] as? Bool == true)
    }

    @Test func showSavedWithTheSwitchOffStillLoads() throws {
        let data = try JSONEncoder().encode(LocalAlbum(name: "Legacy"))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["previewsWhenDisconnected"] = false
        let stored = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LocalAlbum.self, from: stored)
        #expect(decoded.name == "Legacy")

        let resaved = try JSONEncoder().encode(decoded)
        let again = try JSONSerialization.jsonObject(with: resaved) as! [String: Any]
        #expect(again["previewsWhenDisconnected"] as? Bool == true)
    }

    @Test func cloudKitRecordTellsOlderBuildsPracticeIsOn() throws {
        let record = CloudKitRecordMapper.makeShowRecord(from: LocalAlbum(name: "Shared"))
        #expect(
            record[CloudKitSchema.ShowKey.previewsWhenDisconnected] as? Bool == true
        )
    }

    @Test func cloudKitRecordWithTheSwitchOffStillLoads() throws {
        let record = CloudKitRecordMapper.makeShowRecord(from: LocalAlbum(name: "Old Record"))
        record[CloudKitSchema.ShowKey.previewsWhenDisconnected] = false as CKRecordValue
        let decoded = try #require(CloudKitRecordMapper.album(from: record))
        #expect(decoded.name == "Old Record")
    }
}
