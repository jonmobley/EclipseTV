//
//  CaptureStoreUploadFilterTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CaptureStoreUploadFilterTests {

    private func makeStore() throws -> CaptureStore {
        let suite = "CaptureStoreUploadFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return CaptureStore(defaults: defaults)
    }

    @Test func localOnlyCapturesAreExcludedFromUploadIds() throws {
        let store = try makeStore()
        store.upsert(CaptureRecord(
            id: "local-1",
            isVideo: false,
            fileExtension: "jpg",
            syncState: .localOnly
        ))
        // Keep the record local-only even if upsert scheduled a save (test backend
        // is a no-op, but setSyncState makes the filter intent explicit).
        store.setSyncState(id: "local-1", .localOnly)

        #expect(!store.idsNeedingUpload.contains("local-1"))
    }

    @Test func pendingAndSyncedCapturesAreIncluded() throws {
        let store = try makeStore()
        store.upsert(CaptureRecord(
            id: "pending-1",
            isVideo: false,
            fileExtension: "jpg",
            syncState: .pendingUpload
        ))
        store.setSyncState(id: "pending-1", .pendingUpload)
        store.upsert(CaptureRecord(
            id: "synced-1",
            isVideo: false,
            fileExtension: "jpg",
            syncState: .synced
        ))
        store.setSyncState(id: "synced-1", .synced)

        let ids = Set(store.idsNeedingUpload)
        #expect(ids.contains("pending-1"))
        #expect(ids.contains("synced-1"))
    }
}
