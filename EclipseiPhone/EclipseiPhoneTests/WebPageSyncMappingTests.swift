//
//  WebPageSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

struct WebPageSyncMappingTests {

    @Test func recordRoundTripPreservesIdentityURLAndTitle() throws {
        let page = WebPage(
            title: "Example",
            url: URL(string: "https://example.com/path")!
        )
        let record = CloudKitRecordMapper.makeWebPageRecord(from: page)
        #expect(record.recordType == CloudKitSchema.RecordType.webPage)
        #expect(record.recordID.recordName == page.id.uuidString)

        let decoded = try #require(CloudKitRecordMapper.webPage(from: record))
        #expect(decoded.id == page.id)
        #expect(decoded.title == page.title)
        #expect(decoded.url == page.url)
    }

    @Test func showRecordIsNotDecodedAsWebPage() {
        let album = LocalAlbum(name: "Show")
        let record = CloudKitRecordMapper.makeShowRecord(from: album)
        #expect(CloudKitRecordMapper.webPage(from: record) == nil)
    }
}
