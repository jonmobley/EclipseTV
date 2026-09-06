//
//  CountdownControllerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CountdownControllerTests {

    private static let suiteName = "EclipseTV.CountdownControllerTests"

    @Test func displayStringUsesMinutesAndHours() {
        #expect(CountdownController.displayString(seconds: 0) == "0:00")
        #expect(CountdownController.displayString(seconds: 5) == "0:05")
        #expect(CountdownController.displayString(seconds: 75) == "1:15")
        #expect(CountdownController.displayString(seconds: 300) == "5:00")
        #expect(CountdownController.displayString(seconds: 3661) == "1:01:01")
    }

    @Test func defaultDurationIsFiveMinutes() {
        let clock = makeClock()
        #expect(clock.duration == 300)
        #expect(clock.remaining == 300)
        #expect(clock.running == false)
        #expect(clock.displayString == "5:00")
        #expect(clock.tileTitle == "Countdown\n5:00")
    }

    @Test func setDurationResetsRemainingAndPersists() {
        let clock = makeClock()
        clock.setDuration(60)
        #expect(clock.duration == 60)
        #expect(clock.remaining == 60)
        #expect(clock.displayString == "1:00")

        let reloaded = CountdownController(defaults: isolatedDefaults())
        #expect(reloaded.duration == 60)
        #expect(reloaded.remaining == 60)
    }

    @Test func setDurationClampsOutOfRangeValues() {
        let clock = makeClock()
        clock.setDuration(0)
        #expect(clock.duration == 1)
        clock.setDuration(90_000)
        #expect(clock.duration == 24 * 60 * 60)
    }

    @Test func startPauseAndReset() {
        let clock = makeClock()
        clock.setDuration(30)
        clock.start()
        #expect(clock.running)
        clock.pause()
        #expect(clock.running == false)
        #expect(clock.remaining <= 30)

        clock.reset()
        #expect(clock.running == false)
        #expect(clock.remaining == 30)
    }

    @Test func durationPresetsMatchRibbon() {
        #expect(CountdownController.durationPresets == [30, 60, 120, 300, 600])
    }

    @Test func parseDurationAcceptsMinutesAndClockStrings() {
        #expect(CountdownController.parseDuration("7") == 7 * 60)
        #expect(CountdownController.parseDuration("0:45") == 45)
        #expect(CountdownController.parseDuration("7:30") == 7 * 60 + 30)
        #expect(CountdownController.parseDuration("1:15:00") == 75 * 60)
        #expect(CountdownController.parseDuration(" 5:00 ") == 5 * 60)
        #expect(CountdownController.parseDuration("90") == 90 * 60)
    }

    @Test func parseDurationRejectsInvalidInput() {
        #expect(CountdownController.parseDuration("") == nil)
        #expect(CountdownController.parseDuration("  ") == nil)
        #expect(CountdownController.parseDuration("abc") == nil)
        #expect(CountdownController.parseDuration("5:60") == nil)
        #expect(CountdownController.parseDuration("1:90:00") == nil)
        #expect(CountdownController.parseDuration("0") == nil)
        #expect(CountdownController.parseDuration("0:00") == nil)
        #expect(CountdownController.parseDuration("1:2:3:4") == nil)
    }

    @Test func freshClockHasNoExpiry() {
        let clock = makeClock()
        #expect(clock.expiredAt == nil)
        #expect(clock.secondsSinceExpiry == nil)
        #expect(clock.syncRemainingFromDeadline() == false)
    }

    @Test func clockCrossesZeroOnceAndKeepsTheTrueZeroMoment() async throws {
        let clock = makeClock()
        clock.setDuration(1)
        let startedAt = Date()
        clock.start()
        try await Task.sleep(for: .milliseconds(1400))
        // No-op when the timer already crossed zero during the sleep.
        clock.syncRemainingFromDeadline()

        #expect(clock.running == false)
        #expect(clock.remaining == 0)
        #expect(clock.displayString == "0:00")
        // Zero is one second after start, whichever tick happened to notice.
        let expiredAt = try #require(clock.expiredAt)
        #expect(abs(expiredAt.timeIntervalSince(startedAt) - 1) < 0.3)
        let age = try #require(clock.secondsSinceExpiry)
        #expect(age >= 0)
        #expect(age < CountdownEndAction.maximumLateness)
        // The end action must run once, so nothing may cross zero twice.
        #expect(clock.syncRemainingFromDeadline() == false)

        clock.start()
        #expect(clock.expiredAt == nil)
        #expect(clock.secondsSinceExpiry == nil)
        #expect(clock.remaining == 1)
        clock.pause()
    }

    @Test func resetAndEndLiveClearTheExpiryStamp() {
        let clock = makeClock()
        clock.setDuration(30)
        clock.start()
        clock.reset()
        #expect(clock.expiredAt == nil)
        clock.start()
        clock.endLive()
        #expect(clock.expiredAt == nil)
        #expect(clock.liveCountdownId == nil)
    }

    @Test func isPresetDurationIsFalseForCustomLength() {
        let clock = makeClock()
        clock.setDuration(60)
        #expect(clock.isPresetDuration)
        clock.setDuration(7 * 60 + 30)
        #expect(clock.isPresetDuration == false)
    }

    // MARK: - Helpers

    private func makeClock() -> CountdownController {
        let defaults = isolatedDefaults()
        defaults.removePersistentDomain(forName: Self.suiteName)
        return CountdownController(defaults: defaults)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: Self.suiteName) ?? .standard
    }
}
