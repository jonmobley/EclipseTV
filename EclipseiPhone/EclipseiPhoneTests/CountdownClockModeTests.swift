//
//  CountdownClockModeTests.swift
//  EclipseiPhoneTests
//
//  Count Up and To Time on the live clock, driven by a hand-advanced clock.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CountdownClockModeTests {

    private static let suiteName = "EclipseTV.CountdownClockModeTests"
    /// 2026-11-25 17:00:00 UTC.
    private static let fivePM = Date(timeIntervalSince1970: 1_795_626_000)

    // MARK: - Count Up

    @Test func countUpStartsAtZeroCountsUpAndNeverExpires() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        clock.present(makeItem(.init(mode: .countUp)))
        #expect(clock.remaining == 0)
        #expect(clock.isAtEnd == false)
        #expect(clock.displayString == "0:00")

        time.advance(by: 65.4)
        #expect(clock.syncRemainingFromDeadline() == false)
        #expect(clock.remaining == 65)
        #expect(clock.running)

        time.advance(by: 24 * 3600)
        #expect(clock.syncRemainingFromDeadline() == false)
        #expect(clock.running)
        clock.pause()
    }

    @Test func countUpPauseHoldsAndResetReturnsToZero() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        clock.present(makeItem(.init(mode: .countUp)))
        time.advance(by: 30)
        clock.pause()
        time.advance(by: 100)
        #expect(clock.remaining == 30)
        clock.start()
        time.advance(by: 5)
        clock.syncRemainingFromDeadline()
        #expect(clock.remaining == 35)
        clock.reset()
        #expect(clock.remaining == 0)
        #expect(clock.running == false)
    }

    @Test func countUpKeepsElapsedWhenAnotherClockTakesOutput() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        let first = makeItem(.init(mode: .countUp))
        clock.present(first)
        time.advance(by: 42)
        clock.present(makeItem(.init()))
        #expect(clock.heldRemaining(for: first) == 42)
        #expect(clock.startSeconds(for: first) == 42)
        clock.present(first)
        #expect(clock.remaining == 42)
        clock.pause()
    }

    @Test func durationChangeLeavesCountUpFaceAlone() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        clock.present(makeItem(.init(mode: .countUp)))
        time.advance(by: 20)
        clock.syncRemainingFromDeadline()
        clock.setDuration(60)
        #expect(clock.remaining == 20)
        #expect(clock.duration == 60)
        clock.pause()
    }

    // MARK: - To Time

    @Test func toTimeCountsToTheTargetAndExpiresThere() throws {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        let settings = CountdownClockSettings(
            mode: .timeOfDay, targetMinutes: 18 * 60 + 30, targetTimeZone: "UTC"
        )
        clock.present(makeItem(settings))
        #expect(clock.remaining == 90 * 60)
        time.advance(by: 90 * 60 - 1)
        #expect(clock.syncRemainingFromDeadline() == false)
        #expect(clock.remaining == 1)
        time.advance(by: 1)
        #expect(clock.syncRemainingFromDeadline())
        #expect(clock.isAtEnd)
        let target = try #require(settings.targetDate(relativeTo: Self.fivePM))
        #expect(clock.expiredAt == target)
    }

    @Test func toTimeResumeJumpsToTheRealTimeLeft() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        clock.present(makeItem(.init(
            mode: .timeOfDay, targetMinutes: 18 * 60, targetTimeZone: "UTC"
        )))
        time.advance(by: 60)
        clock.pause()
        #expect(clock.remaining == 59 * 60)
        time.advance(by: 600)
        #expect(clock.remaining == 59 * 60)
        clock.start()
        #expect(clock.remaining == 49 * 60)
        clock.pause()
    }

    @Test func toTimePastTargetShowsZeroWithoutRunning() {
        let clock = makeClock(FakeClock(Self.fivePM))
        let item = makeItem(.init(mode: .timeOfDay, targetMinutes: 9 * 60, targetTimeZone: "UTC"))
        clock.present(item)
        #expect(clock.remaining == 0)
        #expect(clock.running == false)
        #expect(clock.isAtEnd)
        #expect(clock.heldRemaining(for: item) == nil)
    }

    // MARK: - Live Edits

    @Test func switchingTheLiveClockToCountUpRestartsFromZero() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        clock.present(makeItem(.init()))
        time.advance(by: 10)
        clock.syncRemainingFromDeadline()
        #expect(clock.remaining == 290)
        clock.adoptClock(.init(mode: .countUp))
        #expect(clock.remaining == 0)
        #expect(clock.running)
        clock.pause()
    }

    @Test func captionChangeDoesNotResetTheFace() {
        let time = FakeClock(Self.fivePM)
        let clock = makeClock(time)
        clock.present(makeItem(.init()))
        time.advance(by: 10)
        clock.syncRemainingFromDeadline()
        clock.adoptClock(.init(caption: "Up next", style: .simple))
        #expect(clock.remaining == 290)
        #expect(clock.clockSettings.caption == "Up next")
        clock.pause()
    }

    // MARK: - Helpers

    private func makeItem(_ settings: CountdownClockSettings) -> ShowCountdown {
        ShowCountdown(showId: UUID(), name: "Timer", duration: 300, clock: settings)
    }

    private func makeClock(_ time: FakeClock) -> CountdownController {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.removePersistentDomain(forName: Self.suiteName)
        return CountdownController(defaults: defaults, now: { time.now })
    }

    /// Wall clock the test advances by hand.
    private final class FakeClock {
        private(set) var now: Date

        init(_ start: Date) { now = start }

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }
}
