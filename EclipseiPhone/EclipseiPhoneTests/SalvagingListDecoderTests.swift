//
//  SalvagingListDecoderTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import OSLog
import Testing
@testable import EclipseiPhone

struct SalvagingListDecoderTests {

    private struct Item: Codable, Equatable {
        let id: Int
        let name: String
    }

    private let key = "SalvagingListDecoderTests.items"
    private let logger = Logger(subsystem: "com.eclipseapp.ios.tests", category: "Salvage")

    private func makeDefaults() throws -> UserDefaults {
        let suite = "SalvagingListDecoderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func decode(from defaults: UserDefaults)
        -> SalvagingListDecoder.Outcome<Item> {
        SalvagingListDecoder.decodeList(
            Item.self,
            forKey: key,
            from: defaults,
            logger: logger
        )
    }

    @Test func missingPayloadLoadsEmptyWithoutBackup() throws {
        let defaults = try makeDefaults()

        let outcome = decode(from: defaults)

        #expect(outcome.elements.isEmpty)
        #expect(outcome.didFailToLoad == false)
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == nil)
    }

    @Test func intactPayloadDecodesWholeList() throws {
        let defaults = try makeDefaults()
        let items = [Item(id: 1, name: "a"), Item(id: 2, name: "b")]
        defaults.set(try JSONEncoder().encode(items), forKey: key)

        let outcome = decode(from: defaults)

        #expect(outcome.elements == items)
        #expect(outcome.didFailToLoad == false)
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == nil)
    }

    @Test func oneBadEntryIsDroppedAndTheRestSurvive() throws {
        let defaults = try makeDefaults()
        // Middle entry is missing `name`, as a partial write or older schema would leave it.
        let json = """
        [{"id":1,"name":"a"},{"id":2},{"id":3,"name":"c"}]
        """
        let raw = try #require(json.data(using: .utf8))
        defaults.set(raw, forKey: key)

        let outcome = decode(from: defaults)

        #expect(outcome.elements == [Item(id: 1, name: "a"), Item(id: 3, name: "c")])
        #expect(outcome.didFailToLoad == false)
        // The original bytes are kept so the dropped entry is still recoverable.
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == raw)
    }

    @Test func unreadablePayloadIsBackedUpInsteadOfLost() throws {
        let defaults = try makeDefaults()
        let raw = try #require("not json at all".data(using: .utf8))
        defaults.set(raw, forKey: key)

        let outcome = decode(from: defaults)

        #expect(outcome.elements.isEmpty)
        #expect(outcome.didFailToLoad)
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == raw)
    }
}
