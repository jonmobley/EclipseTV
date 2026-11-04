//
//  WebAutoScrollerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct WebAutoScrollerTests {

    private func makeScrollView(contentHeight: CGFloat = 2_000, height: CGFloat = 500) -> UIScrollView {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: height))
        scroll.contentSize = CGSize(width: 300, height: contentHeight)
        return scroll
    }

    private func makeScroller(
        scroll: UIScrollView?,
        frames: PrompterControllerTests.FakeFrames? = nil
    ) throws -> WebAutoScroller {
        let suite = "WebAutoScroll.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return WebAutoScroller(
            defaults: defaults,
            frames: frames ?? PrompterControllerTests.FakeFrames(),
            scrollView: { scroll }
        )
    }

    @Test func startScrollsAtBaseRateTimesSpeed() throws {
        let scroll = makeScrollView()
        let frames = PrompterControllerTests.FakeFrames()
        let scroller = try makeScroller(scroll: scroll, frames: frames)
        scroller.setSpeed(2)
        scroller.start()
        #expect(scroller.isRunning)
        #expect(frames.isRunning)
        frames.step(0.5)
        #expect(abs(scroll.contentOffset.y - 40) < 0.001)
    }

    @Test func stopsAtTheBottomAndWhenNothingToScroll() throws {
        let scroll = makeScrollView(contentHeight: 520, height: 500)
        let frames = PrompterControllerTests.FakeFrames()
        let scroller = try makeScroller(scroll: scroll, frames: frames)
        scroller.setSpeed(3)
        scroller.start()
        frames.step(1)
        #expect(scroll.contentOffset.y == 20)
        #expect(!scroller.isRunning)
        #expect(!frames.isRunning)

        let short = makeScrollView(contentHeight: 400, height: 500)
        let idle = try makeScroller(scroll: short)
        idle.start()
        #expect(!idle.isRunning)
    }

    @Test func tapPausesAndResumesWhileDragOnlyPauses() throws {
        let scroll = makeScrollView()
        let frames = PrompterControllerTests.FakeFrames()
        let scroller = try makeScroller(scroll: scroll, frames: frames)
        scroller.start()
        scroller.togglePlayPause()
        #expect(scroller.state == .paused)
        #expect(scroller.isActive)
        #expect(!frames.isRunning)
        frames.step(1)
        #expect(scroll.contentOffset.y == 0)
        scroller.togglePlayPause()
        #expect(scroller.isRunning)
        scroller.pause()
        #expect(scroller.state == .paused)
        scroller.toggle()
        #expect(scroller.state == .off)
        scroller.togglePlayPause()
        #expect(scroller.isRunning)
    }

    @Test func toggleAndStopNotifyAndPersistSpeed() throws {
        let scroll = makeScrollView()
        let suite = "WebAutoScroll.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let scroller = WebAutoScroller(defaults: defaults, frames: PrompterControllerTests.FakeFrames(), scrollView: { scroll })
        var changes = 0
        scroller.onChange = { changes += 1 }
        scroller.toggle()
        #expect(scroller.isRunning)
        scroller.toggle()
        #expect(!scroller.isRunning)
        scroller.setSpeed(9)
        #expect(scroller.speed == 3)
        #expect(changes == 3)
        let again = WebAutoScroller(defaults: defaults, frames: PrompterControllerTests.FakeFrames())
        #expect(again.speed == 3)
    }

    @Test func losingTheScrollViewStops() throws {
        var scroll: UIScrollView? = makeScrollView()
        let frames = PrompterControllerTests.FakeFrames()
        let suite = "WebAutoScroll.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let scroller = WebAutoScroller(defaults: defaults, frames: frames, scrollView: { scroll })
        scroller.start()
        scroll = nil
        frames.step()
        #expect(!scroller.isRunning)
    }

    @Test func speedLabelsReadNaturally() {
        #expect(WebAutoScroller.speedLabel(0.75) == "0.75×")
        #expect(WebAutoScroller.speedLabel(1) == "1×")
        #expect(WebAutoScroller.speedOptions.contains(1))
    }
}

@MainActor
struct WebAutoScrollSpeedBarTests {

    @Test func snapsToQuarterStepsWithinRange() {
        #expect(WebAutoScrollSpeedBar.snappedSpeed(1.1) == 1)
        #expect(WebAutoScrollSpeedBar.snappedSpeed(1.13) == 1.25)
        #expect(WebAutoScrollSpeedBar.snappedSpeed(0.1) == 0.25)
        #expect(WebAutoScrollSpeedBar.snappedSpeed(5) == 3)
    }

    @Test func applyMovesThumbAndLabelWithoutFiring() {
        let bar = WebAutoScrollSpeedBar()
        var fired = 0
        bar.onSpeedChange = { _ in fired += 1 }
        bar.apply(speed: 1.5)
        #expect(bar.slider.value == 1.5)
        #expect(bar.valueLabel.text == "1.5×")
        #expect(fired == 0)
    }
}
