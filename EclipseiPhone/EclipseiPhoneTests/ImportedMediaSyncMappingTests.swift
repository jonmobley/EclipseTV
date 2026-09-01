//
//  ImportedMediaSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct ImportedMediaSyncMappingTests {

    @Test func importedProvenanceRoundTrip() throws {
        let imported = ImportedMediaRecord(
            libraryId: "A1B2C3D4_E5F6_7890_ABCD_EF1234567890.jpg",
            isVideo: false,
            fileExtension: "jpg",
            displayName: "Beach"
        )
        let record = CloudKitRecordMapper.makeImportedMediaRecord(from: imported)
        #expect(record[CloudKitSchema.MediaKey.provenance] as? String == "imported")
        #expect(
            record[CloudKitSchema.MediaKey.libraryId] as? String == imported.libraryId
        )
        #expect(CloudKitRecordMapper.isImportedMedia(record))
        #expect(CloudKitRecordMapper.capture(from: record) == nil)

        let decoded = try #require(CloudKitRecordMapper.importedMedia(from: record))
        #expect(decoded.cloudId == imported.cloudId)
        #expect(decoded.libraryId == imported.libraryId)
        #expect(decoded.displayName == "Beach")
        #expect(decoded.syncState == .remoteOnly)
    }

    @Test func captureProvenanceIsNotImported() {
        let capture = CaptureRecord(isVideo: false, fileExtension: "jpg")
        let record = CloudKitRecordMapper.makeMediaRecord(from: capture)
        #expect(record[CloudKitSchema.MediaKey.provenance] as? String == "captured")
        #expect(!CloudKitRecordMapper.isImportedMedia(record))
        #expect(CloudKitRecordMapper.importedMedia(from: record) == nil)
    }

    @Test func keepIdsIncludeLibraryAndCloudIds() {
        let suite = "ImportedMediaKeepIds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ImportedMediaStore(defaults: defaults)
        let imported = store.register(
            libraryId: "slide.jpg",
            isVideo: false,
            duration: 0,
            orientation: .landscape,
            showId: nil
        )
        #expect(store.keepIds.contains("slide.jpg"))
        #expect(store.keepIds.contains(imported.cloudId))
    }
}
