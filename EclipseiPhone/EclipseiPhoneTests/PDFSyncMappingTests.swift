//
//  PDFSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct PDFSyncMappingTests {

    @Test func recordRoundTripPreservesIdentityAndTitle() throws {
        let doc = SavedPDF(title: "Quarterly Deck")
        let record = CloudKitRecordMapper.makePDFRecord(from: doc)

        #expect(record.recordType == CloudKitSchema.RecordType.pdfDoc)
        #expect(record.recordID.recordName == doc.id.uuidString)

        let decoded = try #require(CloudKitRecordMapper.savedPDF(from: record))
        #expect(decoded.id == doc.id)
        #expect(decoded.title == doc.title)
        #expect(abs(decoded.createdAt.timeIntervalSince(doc.createdAt)) < 1)
    }

    /// A PDF stores `showId` as a field; `parent` is only for share-root Shows.
    @Test func showIdDoesNotSetParentUnlessShareChild() throws {
        let showId = UUID()
        let record = CloudKitRecordMapper.makePDFRecord(
            from: SavedPDF(title: "Menu"),
            showId: showId
        )
        #expect(record[CloudKitSchema.PDFKey.showId] as? String == showId.uuidString)
        #expect(record.parent == nil)
    }

    @Test func shareChildSetsParentReference() throws {
        let showId = UUID()
        let record = CloudKitRecordMapper.makePDFRecord(
            from: SavedPDF(title: "Menu"),
            showId: showId,
            attachAsShareChild: true
        )
        let parent = try #require(record.parent)
        #expect(parent.recordID == CloudKitSchema.showRecordID(for: showId))
    }

    @Test func withoutShowIdThereIsNoParent() {
        let record = CloudKitRecordMapper.makePDFRecord(from: SavedPDF(title: "Loose"))
        #expect(record.parent == nil)
        #expect(record[CloudKitSchema.PDFKey.showId] == nil)
    }

    @Test func fileIsAttachedAsAsset() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let record = CloudKitRecordMapper.makePDFRecord(
            from: SavedPDF(title: "Attached"),
            assetURL: url
        )
        #expect(CloudKitRecordMapper.pdfAssetURL(from: record) == url)
    }

    @Test func missingFileStillProducesMetadataRecord() {
        let record = CloudKitRecordMapper.makePDFRecord(from: SavedPDF(title: "No File"))
        #expect(CloudKitRecordMapper.pdfAssetURL(from: record) == nil)
        #expect(record[CloudKitSchema.PDFKey.title] as? String == "No File")
    }

    /// Show and PDF record names are both bare UUIDs, so type must be checked.
    @Test func showRecordIsNotDecodedAsPDF() {
        let album = LocalAlbum(name: "Show")
        let record = CloudKitRecordMapper.makeShowRecord(from: album)
        #expect(CloudKitRecordMapper.savedPDF(from: record) == nil)
    }
}
