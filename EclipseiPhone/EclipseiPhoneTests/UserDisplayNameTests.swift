//
//  UserDisplayNameTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct UserDisplayNameTests {

    @Test func normalizedTrimsAndRejectsEmpty() {
        #expect(UserDisplayName.normalized("  ") == nil)
        #expect(UserDisplayName.normalized("") == nil)
        #expect(UserDisplayName.normalized("  Show  ") == "Show")
    }

    @Test func normalizedClampsToMaxLength() {
        let long = String(repeating: "a", count: UserDisplayName.maxLength + 10)
        let result = UserDisplayName.normalized(long)
        #expect(result?.count == UserDisplayName.maxLength)
    }

    @Test func clampPreservesShortTitles() {
        #expect(UserDisplayName.clamp("Home") == "Home")
    }
}
