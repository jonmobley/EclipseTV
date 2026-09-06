//
//  CountdownEndDecisionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CountdownEndDecisionTests {

    @Test func runsWhenTheClockOwnsOutputAndJustExpired() {
        #expect(decide() == .run)
    }

    @Test func holdActionNeverTakesOverOutput() {
        #expect(decide(action: .hold) == .hold)
    }

    @Test func bothNonHoldActionsRunUnderTheSameConditions() {
        #expect(decide(action: .black) == .run)
        #expect(decide(action: .next) == .run)
    }

    @Test func skipsWhenTheClockIsNoLongerTheLiveOverlay() {
        #expect(decide(isCountdownLive: false) == .hold)
    }

    @Test func skipsOnARemoteOperatorSoOutputSwitchesOnlyOnce() {
        #expect(decide(isRemoteOperator: true) == .hold)
    }

    @Test func skipsWhileLiveOutputIsLocked() {
        #expect(decide(isOutputLocked: true) == .hold)
    }

    @Test func skipsWhenTheClockHasNotRunOut() {
        #expect(decide(secondsSinceExpiry: nil) == .hold)
    }

    @Test func skipsAnExpiryTheSleepingPhoneOnlyJustNoticed() {
        let late = CountdownEndAction.maximumLateness
        #expect(decide(secondsSinceExpiry: late) == .run)
        #expect(decide(secondsSinceExpiry: late + 1) == .hold)
        #expect(decide(secondsSinceExpiry: 600) == .hold)
    }

    // MARK: - Helpers

    private func decide(
        action: CountdownEndAction = .next,
        isCountdownLive: Bool = true,
        isRemoteOperator: Bool = false,
        isOutputLocked: Bool = false,
        secondsSinceExpiry: TimeInterval? = 0.25
    ) -> CountdownEndDecision {
        CountdownEndDecision.decide(
            action: action,
            isCountdownLive: isCountdownLive,
            isRemoteOperator: isRemoteOperator,
            isOutputLocked: isOutputLocked,
            secondsSinceExpiry: secondsSinceExpiry
        )
    }
}
