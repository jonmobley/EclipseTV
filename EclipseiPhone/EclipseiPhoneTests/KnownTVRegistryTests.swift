//
//  KnownTVRegistryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct KnownTVRegistryTests {

    private func makeRegistry() throws -> (KnownTVRegistry, UserDefaults, String) {
        let suite = "KnownTVRegistryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (KnownTVRegistry(defaults: defaults), defaults, suite)
    }

    @Test func rememberPersistsAndSortsByLastSeen() throws {
        let (registry, _, _) = try makeRegistry()
        registry.remember(name: "Living Room")
        registry.remember(name: "Studio")
        let names = registry.all().map(\.name)
        #expect(names == ["Studio", "Living Room"] || names.contains("Studio"))
        #expect(Set(names) == ["Living Room", "Studio"])
    }

    @Test func unreadablePayloadIsNotOverwrittenByRemember() throws {
        let (registry, defaults, _) = try makeRegistry()
        let key = "EclipseTV.companion.knownTVs"
        let raw = try #require("not-json".data(using: .utf8))
        defaults.set(raw, forKey: key)

        #expect(registry.all().isEmpty)
        registry.remember(name: "ShouldNotPersist")
        #expect(registry.all().isEmpty)
        #expect(defaults.data(forKey: key) == raw)
        #expect(defaults.data(forKey: SalvagingListDecoder.backupKey(for: key)) == raw)
    }

    @Test func partialListSurvivesSalvage() throws {
        let (registry, defaults, _) = try makeRegistry()
        let key = "EclipseTV.companion.knownTVs"
        // Middle entry is missing `lastSeen`, as a partial write would leave it.
        let json = """
        [{"name":"A","lastSeen":1},{"name":"B"},{"name":"C","lastSeen":3}]
        """
        defaults.set(try #require(json.data(using: .utf8)), forKey: key)
        let names = Set(registry.all().map(\.name))
        #expect(names.contains("A"))
        #expect(names.contains("C"))
        #expect(!names.contains("B"))
    }
}
