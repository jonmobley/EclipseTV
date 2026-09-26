//
//  EclipseSyncStatusSummaryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct EclipseSyncStatusSummaryTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func healthyWithoutHistoryIsJustOn() {
        #expect(
            EclipseSyncStatusSummary.text(pauseReason: nil, lastSyncedAt: nil, now: now) == "On"
        )
    }

    @Test func recentSyncSaysJustNow() {
        let text = EclipseSyncStatusSummary.text(
            pauseReason: nil, lastSyncedAt: now.addingTimeInterval(-20), now: now
        )
        #expect(text == "On · Synced just now")
    }

    @Test func olderSyncUsesARelativePhrase() {
        let text = EclipseSyncStatusSummary.text(
            pauseReason: nil, lastSyncedAt: now.addingTimeInterval(-7_200), now: now
        )
        #expect(text.hasPrefix("On · Synced "))
        #expect(text.contains("hour"))
    }

    @Test func pauseReasonWinsOverHistory() {
        let text = EclipseSyncStatusSummary.text(
            pauseReason: .noAccount, lastSyncedAt: now, now: now
        )
        #expect(text == "Paused · Not signed in to iCloud")
        #expect(
            EclipseSyncStatusSummary.shortReason(.quotaExceeded) == "iCloud storage is full"
        )
        #expect(
            EclipseSyncStatusSummary.shortReason(.temporarilyUnavailable("x"))
                == "iCloud unavailable"
        )
    }

    @MainActor
    @Test func lastSyncedSurvivesRelaunch() throws {
        let suite = "EclipseSyncActivityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = EclipseSyncActivity(defaults: defaults)
        #expect(first.lastSyncedAt == nil)
        first.noteSyncCompleted(at: now)

        let relaunched = EclipseSyncActivity(defaults: defaults)
        #expect(relaunched.lastSyncedAt == now)
    }
}
