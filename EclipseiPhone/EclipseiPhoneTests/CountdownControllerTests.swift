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

    @Test func durationPresetsMatchMenu() {
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

    @Test func clockCrossesZeroOnceAndKeepsTheTrueZeroMoment() throws {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        clock.setDuration(1)
        let startedAt = time.now
        clock.start()

        time.advance(by: 0.5)
        #expect(clock.syncRemainingFromDeadline() == false)
        #expect(clock.running)
        #expect(clock.remaining == 1)

        // A tick that lands late still crosses zero once.
        time.advance(by: 0.9)
        #expect(clock.syncRemainingFromDeadline() == true)
        #expect(clock.running == false)
        #expect(clock.remaining == 0)
        #expect(clock.displayString == "0:00")
        // Zero is one second after start, whichever tick happened to notice.
        let expiredAt = try #require(clock.expiredAt)
        #expect(expiredAt == startedAt.addingTimeInterval(1))
        let age = try #require(clock.secondsSinceExpiry)
        #expect(abs(age - 0.4) < 0.001)
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

    /// Going live publishes the overlay between the bind and the start, so the bind
    /// itself must stay silent: a tick announced here repaints the Show grid from
    /// the program the user is leaving, and while a countdown is already live that
    /// repaint is the last one the tiles get.
    @Test func preparingATimerBindsItWithoutAnnouncingTheChange() {
        let clock = makeClock()
        let item = ShowCountdown(showId: UUID(), name: "Doors", duration: 90)

        var announcements = 0
        let token = NotificationCenter.default.addObserver(
            forName: CountdownController.didChangeNotification,
            object: clock,
            queue: nil
        ) { _ in
            announcements += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        clock.prepare(item)
        #expect(clock.liveCountdownId == item.id)
        #expect(clock.duration == 90)
        #expect(clock.remaining == 90)
        #expect(clock.running == false)
        #expect(announcements == 0)

        clock.start()
        #expect(clock.running)
        #expect(announcements == 1)
        clock.pause()
    }

    @Test func preparingASecondTimerReplacesTheFirst() {
        let clock = makeClock()
        let first = ShowCountdown(showId: UUID(), name: "Break", duration: 60)
        let second = ShowCountdown(showId: UUID(), name: "Doors", duration: 90)
        clock.prepare(first)
        clock.start()
        clock.prepare(second)
        #expect(clock.liveCountdownId == second.id)
        #expect(clock.duration == 90)
        #expect(clock.remaining == 90)
        clock.pause()
    }

    @Test func isPresetDurationIsFalseForCustomLength() {
        let clock = makeClock()
        clock.setDuration(60)
        #expect(clock.isPresetDuration)
        clock.setDuration(7 * 60 + 30)
        #expect(clock.isPresetDuration == false)
    }

    // MARK: - Held Time

    @Test func cuttingAwayHoldsTheRemainderAndComingBackResumesIt() {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        let timer = makeCountdown(duration: 300)

        clock.present(timer)
        #expect(clock.remaining == 300)
        time.advance(by: 100)
        clock.syncRemainingFromDeadline()
        #expect(clock.remaining == 200)

        // A video going live tears the countdown overlay down.
        clock.endLive()
        #expect(clock.liveCountdownId == nil)
        #expect(clock.running == false)
        #expect(clock.heldRemaining(for: timer) == 200)
        #expect(clock.startSeconds(for: timer) == 200)

        // Time under the video is not charged to a clock that is not running.
        time.advance(by: 500)
        #expect(clock.heldRemaining(for: timer) == 200)

        clock.present(timer)
        #expect(clock.running)
        #expect(clock.remaining == 200)
        #expect(clock.heldRemaining(for: timer) == nil)
        clock.pause()
    }

    @Test func eachCountdownKeepsItsOwnPlaceAcrossADirectSwap() {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        let first = makeCountdown(duration: 300)
        let second = makeCountdown(duration: 60)

        clock.present(first)
        time.advance(by: 100)
        clock.syncRemainingFromDeadline()

        // Countdown → countdown never reaches overlay teardown, so `present`
        // is what has to hold the clock it replaces.
        clock.present(second)
        #expect(clock.liveCountdownId == second.id)
        #expect(clock.duration == 60)
        #expect(clock.remaining == 60)
        #expect(clock.heldRemaining(for: first) == 200)

        time.advance(by: 20)
        clock.syncRemainingFromDeadline()
        #expect(clock.remaining == 40)

        clock.present(first)
        #expect(clock.remaining == 200)
        #expect(clock.heldRemaining(for: second) == 40)
        clock.pause()
    }

    @Test func representingTheLiveCountdownStartsItOver() {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        let timer = makeCountdown(duration: 300)

        clock.present(timer)
        time.advance(by: 100)
        clock.syncRemainingFromDeadline()
        #expect(clock.remaining == 200)

        // The hold files 200 for this very tile, and the same tap must not then
        // resume from it.
        clock.present(timer)
        #expect(clock.remaining == 300)
        #expect(clock.heldRemaining(for: timer) == nil)
        clock.pause()
    }

    @Test func anExpiredClockStartsOverRatherThanResuming() {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        let timer = makeCountdown(duration: 30)

        clock.present(timer)
        time.advance(by: 30)
        #expect(clock.syncRemainingFromDeadline())
        #expect(clock.remaining == 0)

        clock.endLive()
        #expect(clock.heldRemaining(for: timer) == nil)
        #expect(clock.startSeconds(for: timer) == 30)

        clock.present(timer)
        #expect(clock.remaining == 30)
        clock.pause()
    }

    @Test func aClockStoppedAtFullLengthHasNothingToHold() {
        let clock = makeClock()
        let timer = makeCountdown(duration: 120)

        clock.present(timer)
        clock.reset()
        clock.endLive()
        #expect(clock.heldRemaining(for: timer) == nil)
        #expect(clock.startSeconds(for: timer) == 120)
    }

    @Test func editingTheTileLengthInvalidatesTheHold() {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        var timer = makeCountdown(duration: 300)

        clock.present(timer)
        time.advance(by: 100)
        clock.syncRemainingFromDeadline()
        clock.endLive()
        #expect(clock.heldRemaining(for: timer) == 200)

        // Choosing a new length is asking for that length.
        timer.duration = 600
        #expect(clock.heldRemaining(for: timer) == nil)
        #expect(clock.startSeconds(for: timer) == 600)
    }

    @Test func discardingHeldTimeStartsTheNextTapOver() {
        let time = FakeClock()
        let clock = makeClock(now: { time.now })
        let timer = makeCountdown(duration: 300)

        clock.present(timer)
        time.advance(by: 100)
        clock.syncRemainingFromDeadline()
        clock.endLive()
        #expect(clock.heldRemaining(for: timer) == 200)

        clock.discardHeldTime(for: timer.id)
        #expect(clock.heldRemaining(for: timer) == nil)
        #expect(clock.startSeconds(for: timer) == 300)

        clock.present(timer)
        #expect(clock.remaining == 300)
        clock.pause()
    }

    // MARK: - Helpers

    private func makeCountdown(duration: Int) -> ShowCountdown {
        ShowCountdown(showId: UUID(), name: "Countdown", duration: duration)
    }

    private func makeClock(
        now: @escaping () -> Date = { Date() }
    ) -> CountdownController {
        let defaults = isolatedDefaults()
        defaults.removePersistentDomain(forName: Self.suiteName)
        return CountdownController(defaults: defaults, now: now)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    /// Wall clock the test advances by hand.
    private final class FakeClock {
        private(set) var now = Date(timeIntervalSinceReferenceDate: 1_000_000)

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }
}
