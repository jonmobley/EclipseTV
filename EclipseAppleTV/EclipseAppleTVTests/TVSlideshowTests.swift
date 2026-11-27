//
//  TVSlideshowTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseAppleTV

/// Slide timing, stepping, looping and stop rules for TV-run slideshows.
struct TVSlideshowPlanTests {

    static func dto(
        _ ids: [String], start: Int = 0, seconds: Double? = 5,
        loops: Bool = false, crossfades: Bool = true
    ) -> SlideshowDTO {
        SlideshowDTO(
            slides: ids.map { SlideshowSlideDTO(id: $0) },
            startIndex: start, seconds: seconds, loops: loops, crossfades: crossfades
        )
    }

    @Test func dropsSlidesTheTVDoesNotHave() throws {
        let plan = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b", "c"], start: 2)) { $0 != "b" })
        #expect(plan.slideIds == ["a", "c"])
        #expect(plan.currentId == "c")
    }

    @Test func noSlidesOnTheTVMeansNoPlan() {
        #expect(TVSlideshowPlan(dto: Self.dto(["a"])) { _ in false } == nil)
    }

    @Test func startSlideMissingFallsBackToFirst() throws {
        let plan = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b", "c"], start: 1)) { $0 != "b" })
        #expect(plan.currentId == "a")
    }

    @Test func secondsAreClampedAndOptional() throws {
        let tiny = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b"], seconds: 0.01)) { _ in true })
        #expect(tiny.seconds == TVSlideshowPlan.minimumSeconds)
        let manual = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b"], seconds: nil)) { _ in true })
        #expect(manual.seconds == nil)
        #expect(manual.autoAdvances == false)
        let single = try #require(TVSlideshowPlan(dto: Self.dto(["a"])) { _ in true })
        #expect(single.autoAdvances == false)
    }

    @Test func advancesThenStopsAtTheEndWithoutLoop() throws {
        let plan = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b"])) { _ in true })
        let second = try #require(plan.advanced())
        #expect(second.currentId == "b")
        #expect(second.advanced() == nil)
    }

    @Test func loopWrapsToTheFirstSlide() throws {
        let plan = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b"], start: 1, loops: true)) { _ in true })
        #expect(plan.advanced()?.currentId == "a")
    }

    @Test func jumpGoesToKnownSlidesOnly() throws {
        let plan = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b", "c"])) { _ in true })
        #expect(plan.jumped(toId: "c")?.currentId == "c")
        #expect(plan.jumped(toId: "zzz") == nil)
    }

    @Test func removingASlideKeepsThePlaceSensibly() throws {
        let plan = try #require(TVSlideshowPlan(dto: Self.dto(["a", "b", "c"], start: 2)) { _ in true })
        let without = try #require(plan.removing(id: "a"))
        #expect(without.slideIds == ["b", "c"])
        #expect(without.currentId == "c")
        let lastGone = try #require(plan.removing(id: "c"))
        #expect(lastGone.currentId == "a")
        let one = try #require(TVSlideshowPlan(dto: Self.dto(["a"])) { _ in true })
        #expect(one.removing(id: "a") == nil)
    }

    @Test func onlyMessagesThatReplaceTheScreenStopASlideshow() {
        #expect(TVSlideshowInterruption.stops(.playRequest))
        #expect(TVSlideshowInterruption.stops(.setIdleMode))
        #expect(TVSlideshowInterruption.stops(.setDisplayMode))
        #expect(!TVSlideshowInterruption.stops(.slideshowControl))
        #expect(!TVSlideshowInterruption.stops(.setContentTransition))
        #expect(!TVSlideshowInterruption.stops(.setImageFit))
        #expect(!TVSlideshowInterruption.stops(.setLibraryAlbums))
        #expect(!TVSlideshowInterruption.stops(nil))
    }
}

/// The timer-driven player, with time driven by hand.
@MainActor
struct TVSlideshowPlayerTests {

    /// A player whose "timer" just records the wait it was asked for.
    @MainActor private final class Harness {
        let player = TVSlideshowPlayer()
        var shown: [(id: String, crossfade: Bool)] = []
        var waits: [TimeInterval] = []
        var missing: Set<String> = []

        init() {
            player.presentSlide = { [unowned self] id, crossfade in
                guard !self.missing.contains(id) else { return false }
                self.shown.append((id, crossfade))
                return true
            }
            player.scheduleTimer = { [unowned self] seconds, _ in
                self.waits.append(seconds)
                return nil
            }
        }
    }

    private func plan(
        _ ids: [String], start: Int = 0, seconds: Double? = 5, loops: Bool = false
    ) -> TVSlideshowPlan? {
        TVSlideshowPlan(
            dto: TVSlideshowPlanTests.dto(ids, start: start, seconds: seconds, loops: loops, crossfades: true)
        ) { _ in true }
    }

    @Test func startShowsTheStartSlideAndWaits() throws {
        let harness = Harness()
        harness.player.start(try #require(plan(["a", "b"], start: 1, loops: true)))
        #expect(harness.shown.map(\.id) == ["b"])
        #expect(harness.shown.first?.crossfade == true)
        #expect(harness.waits == [5])
        #expect(harness.player.isRunning)
    }

    @Test func timerAdvancesAndLoops() throws {
        let harness = Harness()
        harness.player.start(try #require(plan(["a", "b"], loops: true)))
        harness.player.timerFired()
        harness.player.timerFired()
        #expect(harness.shown.map(\.id) == ["a", "b", "a"])
        #expect(harness.waits.count == 3)
    }

    @Test func endWithoutLoopStopsOnTheLastSlide() throws {
        let harness = Harness()
        harness.player.start(try #require(plan(["a", "b"])))
        harness.player.timerFired()
        harness.player.timerFired()
        #expect(harness.shown.map(\.id) == ["a", "b"])
        #expect(!harness.player.isRunning)
    }

    @Test func phoneStepJumpsAndRestartsTheWait() throws {
        let harness = Harness()
        harness.player.start(try #require(plan(["a", "b", "c"])))
        #expect(harness.player.goTo(id: "c"))
        #expect(harness.shown.map(\.id) == ["a", "c"])
        #expect(harness.waits == [5, 5])
        #expect(!harness.player.goTo(id: "nope"))
    }

    @Test func manualSlideshowNeverWaits() throws {
        let harness = Harness()
        harness.player.start(try #require(plan(["a", "b"], seconds: nil)))
        harness.player.goTo(id: "b")
        #expect(harness.waits.isEmpty)
        #expect(harness.player.isRunning)
    }

    @Test func slidesTheTVLostAreSkipped() throws {
        let harness = Harness()
        harness.missing = ["b"]
        harness.player.start(try #require(plan(["a", "b", "c"])))
        harness.player.timerFired()
        #expect(harness.shown.map(\.id) == ["a", "c"])
        #expect(harness.player.plan?.slideIds == ["a", "c"])
    }

    @Test func stopKeepsTheSlideAndIgnoresLateTimers() throws {
        let harness = Harness()
        harness.player.start(try #require(plan(["a", "b"])))
        harness.player.stop()
        harness.player.timerFired()
        #expect(harness.shown.map(\.id) == ["a"])
        #expect(!harness.player.isRunning)
    }
}
