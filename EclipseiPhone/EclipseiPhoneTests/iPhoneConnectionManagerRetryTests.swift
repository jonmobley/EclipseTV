//
//  iPhoneConnectionManagerRetryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Covers the reconnect-retry bookkeeping hardened in the concurrency pass:
//  - scheduling increments the attempt count and arms a timer,
//  - resetRetryCount() clears both,
//  - pausing auto-connect (autoConnectEnabled = false) also clears retry state,
//    so a stale timer can't fire a reconnect after the user goes offline.
//
//  These run on the main actor because retry state is main-thread-only by design.
//

import Testing
import Foundation
import MultipeerConnectivity
@testable import EclipseiPhone

@MainActor
struct iPhoneConnectionManagerRetryTests {

    private func peer() -> MCPeerID { MCPeerID(displayName: "TestTV-\(UUID().uuidString)") }

    @Test func schedulingArmsTimerAndIncrementsCount() {
        let sut = iPhoneConnectionManager()
        #expect(sut.retryCount == 0)
        #expect(sut.retryTimer == nil)

        sut.scheduleReconnectAttempt(to: peer())

        #expect(sut.retryCount == 1)
        #expect(sut.retryTimer != nil)

        // Don't leave a live timer running past the test.
        sut.resetRetryCount()
    }

    @Test func resetClearsCountAndTimer() {
        let sut = iPhoneConnectionManager()
        sut.scheduleReconnectAttempt(to: peer())
        #expect(sut.retryCount == 1)

        sut.resetRetryCount()

        #expect(sut.retryCount == 0)
        #expect(sut.retryTimer == nil)
    }

    @Test func schedulingStopsAtMaxRetries() {
        let sut = iPhoneConnectionManager()
        let target = peer()

        // maxRetries is 3: three schedules climb to 3, the fourth trips the cap and resets.
        sut.scheduleReconnectAttempt(to: target)
        sut.scheduleReconnectAttempt(to: target)
        sut.scheduleReconnectAttempt(to: target)
        #expect(sut.retryCount == sut.maxRetries)

        sut.scheduleReconnectAttempt(to: target)
        #expect(sut.retryCount == 0)

        sut.resetRetryCount()
    }

    @Test func pausingAutoConnectResetsRetryState() {
        let sut = iPhoneConnectionManager()
        sut.scheduleReconnectAttempt(to: peer())
        #expect(sut.retryCount == 1)
        #expect(sut.retryTimer != nil)

        // Going offline must cancel any pending backoff retry.
        sut.autoConnectEnabled = false

        #expect(sut.retryCount == 0)
        #expect(sut.retryTimer == nil)
    }

    @Test func disconnectResetsRetryState() {
        let sut = iPhoneConnectionManager()
        sut.scheduleReconnectAttempt(to: peer())
        #expect(sut.retryCount == 1)

        sut.disconnect()

        #expect(sut.retryCount == 0)
        #expect(sut.retryTimer == nil)
    }
}
