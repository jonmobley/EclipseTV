//
//  AlreadyInShowAlertTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct AlreadyInShowAlertTests {

    @Test func needsConfirmationWhenSelectionOverlapsMembers() {
        #expect(
            AlreadyInShowAlert.needsConfirmation(
                selectedIds: ["a", "b"],
                memberIds: ["b"]
            )
        )
    }

    @Test func skipsConfirmationWhenSelectionIsNew() {
        #expect(
            !AlreadyInShowAlert.needsConfirmation(
                selectedIds: ["a", "b"],
                memberIds: ["c"]
            )
        )
    }

    @Test func skipsConfirmationWhenSelectionIsEmpty() {
        #expect(
            !AlreadyInShowAlert.needsConfirmation(
                selectedIds: [],
                memberIds: ["a"]
            )
        )
    }
}
