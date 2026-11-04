//
//  PrompterScrollEngineTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Foundation
import Testing
@testable import EclipseiPhone

struct PrompterScrollEngineTests {

    @Test func advanceMovesAtBaseRateTimesSpeed() {
        var engine = PrompterScrollEngine()
        engine.isPlaying = true
        engine.speed = 2
        engine.advance(by: 0.5)
        #expect(engine.offset == PrompterScrollEngine.basePointsPerSecond * 2 * 0.5)
    }

    @Test func advanceDoesNothingWhilePaused() {
        var engine = PrompterScrollEngine()
        engine.advance(by: 1)
        #expect(engine.offset == 0)
    }

    @Test func speedIsClampedOnAdvance() {
        var engine = PrompterScrollEngine()
        engine.isPlaying = true
        engine.speed = 99
        engine.advance(by: 1)
        #expect(engine.offset == PrompterScrollEngine.basePointsPerSecond * CGFloat(PrompterScrollEngine.maximumSpeed))
    }

    @Test func fingerDraggingDownRewinds() {
        var engine = PrompterScrollEngine()
        engine.offset = 100
        engine.applyScrollDelta(30, synthesizesMomentum: false)
        #expect(engine.offset == 70)
        #expect(engine.velocity == 0)
    }

    @Test func releaseVelocityIsCappedAndCoastsThenStops() {
        var engine = PrompterScrollEngine()
        engine.offset = 200
        engine.release(velocity: 10_000)
        #expect(engine.velocity == PrompterScrollEngine.maximumReleaseVelocity)
        var ticks = 0
        while engine.tickInteraction(deltaTime: 1 / 60, lineHeight: 40, maxOffset: 10_000, scrubDetent: false) {
            ticks += 1
            #expect(ticks < 600)
        }
        #expect(engine.offset > 200)
        #expect(engine.velocity == 0)
    }

    @Test func settleLandsOnTheNearestLine() {
        var engine = PrompterScrollEngine()
        engine.offset = 95
        engine.beginSettleToCenter()
        var ticks = 0
        while engine.tickInteraction(deltaTime: 1 / 60, lineHeight: 40, maxOffset: 1_000, scrubDetent: false) {
            ticks += 1
            #expect(ticks < 600)
        }
        #expect(engine.offset == 80)
        #expect(!engine.isSettling)
    }

    @Test func nearestCenteredOffsetRoundsToLinesAndClamps() {
        var engine = PrompterScrollEngine()
        engine.offset = 61
        #expect(engine.nearestCenteredOffset(lineHeight: 40, maxOffset: 1_000) == 80)
        engine.offset = 990
        #expect(engine.nearestCenteredOffset(lineHeight: 40, maxOffset: 1_000) == 1_000)
        engine.offset = -5
        #expect(engine.nearestCenteredOffset(lineHeight: 40, maxOffset: 1_000) == 0)
    }

    @Test func clampKillsOutwardVelocity() {
        var engine = PrompterScrollEngine()
        engine.offset = 500
        engine.velocity = 300
        engine.clamp(to: 400)
        #expect(engine.offset == 400)
        #expect(engine.velocity == 0)
        engine.offset = -10
        engine.velocity = -50
        engine.clamp(to: 400)
        #expect(engine.offset == 0)
        #expect(engine.velocity == 0)
    }

    @Test func resetAndSetOffsetCancelSettle() {
        var engine = PrompterScrollEngine()
        engine.offset = 120
        engine.beginSettleToCenter()
        engine.reset()
        #expect(engine.offset == 0)
        #expect(!engine.isSettling)
        engine.release(velocity: 100)
        engine.setOffset(77)
        #expect(engine.offset == 77)
        #expect(engine.velocity == 0)
    }
}
