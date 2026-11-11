//
//  QuestPollHostControlsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

@MainActor
struct QuestPollHostControlsTests {

    @Test func timeLeftReadsAsAClock() {
        #expect(QuestPollHostViewController.timeLeftText(12_000) == "0:12")
        #expect(QuestPollHostViewController.timeLeftText(65_400) == "1:06")
        #expect(QuestPollHostViewController.timeLeftText(0) == "—")
        #expect(QuestPollHostViewController.timeLeftText(nil) == "—")
    }

    @Test func joinedShowsTheCapOnlyForCappedRooms() {
        #expect(QuestPollHostViewController.joinedValue(joined: 12, limit: nil) == "12")
        #expect(QuestPollHostViewController.joinedValue(joined: 12, limit: 300) == "12")
        #expect(QuestPollHostViewController.joinedValue(joined: 12, limit: 50) == "12/50")
    }
}
