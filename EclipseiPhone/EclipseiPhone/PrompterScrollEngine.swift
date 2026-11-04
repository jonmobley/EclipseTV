//
//  PrompterScrollEngine.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Foundation

/// Pure scroll maths for the Prompter (play + line snap), ported from the Mac app.
///
/// Speed is a unitless multiplier over `basePointsPerSecond`. Finger scrubs update
/// `offset` directly; on release the stored velocity coasts and then springs toward
/// the nearest script line centred in the viewport. `offset` is measured in the
/// script's own text coordinates (0 = first line on the reading guide), so it does
/// not depend on the viewport height.
struct PrompterScrollEngine: Equatable, Sendable {

    // MARK: - Constants

    /// Scroll rate at speed `1.0` (points per second).
    static let basePointsPerSecond: CGFloat = 40

    /// Allowed speed multipliers.
    static let minimumSpeed: Double = 0.25
    static let maximumSpeed: Double = 3.0
    static let defaultSpeed: Double = 1.0

    /// Exponential friction for coasting after a scrub (1/s).
    static let momentumFriction: CGFloat = 5.5

    /// Spring strength toward the centred line (1/s).
    static let snapSpring: CGFloat = 18

    /// Soft detent strength while the finger is still moving (1/s).
    static let scrubSnapSpring: CGFloat = 3.5

    /// Stop residual coasting under this speed (points/s).
    static let settleVelocity: CGFloat = 2.5

    /// Finish the snap when within this distance of the target (points).
    static let settleDistance: CGFloat = 0.4

    /// Fastest coasting a scrub release can leave behind (points/s).
    static let maximumReleaseVelocity: CGFloat = 4000

    // MARK: - Properties

    /// Points scrolled from the top of the script.
    var offset: CGFloat = 0

    /// Coasting velocity left by a scrub release.
    var velocity: CGFloat = 0

    /// When true, firmly settle to the nearest centred line.
    var isSettling: Bool = false

    /// When true, `advance(by:)` increases `offset`.
    var isPlaying: Bool = false

    /// Multiplier over `basePointsPerSecond` (clamped on advance).
    var speed: Double = Self.defaultSpeed

    // MARK: - Public Interface

    /// Advances the offset by `deltaTime` seconds when playing.
    mutating func advance(by deltaTime: TimeInterval) {
        guard isPlaying, deltaTime > 0 else { return }
        let clampedSpeed = min(max(speed, Self.minimumSpeed), Self.maximumSpeed)
        offset += CGFloat(deltaTime) * Self.basePointsPerSecond * CGFloat(clampedSpeed)
    }

    /// Applies a finger (or wheel) delta to the offset.
    ///
    /// Positive `deltaY` rewinds toward the top, matching a finger dragging down.
    /// When `synthesizesMomentum` is true the delta also feeds coasting velocity.
    mutating func applyScrollDelta(_ deltaY: CGFloat, synthesizesMomentum: Bool) {
        guard deltaY != 0 else { return }
        offset -= deltaY
        isSettling = false
        if synthesizesMomentum {
            velocity -= deltaY * 16
        } else {
            velocity = 0
        }
    }

    /// Stores the coasting velocity a scrub left behind (points/s, offset direction).
    mutating func release(velocity released: CGFloat) {
        velocity = min(max(released, -Self.maximumReleaseVelocity), Self.maximumReleaseVelocity)
        isSettling = false
    }

    /// Begins a firm spring settle to the nearest viewport-centred line.
    mutating func beginSettleToCenter() {
        isSettling = true
    }

    /// Integrates coasting and magnetic line snap for one frame.
    /// - Returns: `true` when momentum / snap still needs further ticks.
    @discardableResult
    mutating func tickInteraction(
        deltaTime: TimeInterval,
        lineHeight: CGFloat,
        maxOffset: CGFloat,
        scrubDetent: Bool
    ) -> Bool {
        guard deltaTime > 0 else { return needsInteractionTicks }
        let dt = CGFloat(deltaTime)
        integrateMomentum(deltaTime: dt)
        applySnap(deltaTime: dt, lineHeight: lineHeight, maxOffset: maxOffset, scrubDetent: scrubDetent)
        clamp(to: maxOffset)
        return needsInteractionTicks
    }

    /// Whether the owner should keep ticking while not playing.
    var needsInteractionTicks: Bool {
        abs(velocity) > Self.settleVelocity || isSettling
    }

    /// Returns to the top of the script without changing play state.
    mutating func reset() {
        offset = 0
        velocity = 0
        isSettling = false
    }

    /// Sets the offset directly, cancelling momentum and settle so it sticks.
    mutating func setOffset(_ value: CGFloat) {
        offset = value
        velocity = 0
        isSettling = false
    }

    /// Clamps `offset` into `0...max(0, maxOffset)` and kills outward velocity.
    mutating func clamp(to maxOffset: CGFloat) {
        let upper = max(0, maxOffset)
        if offset < 0 {
            offset = 0
            if velocity < 0 { velocity = 0 }
        } else if offset > upper {
            offset = upper
            if velocity > 0 { velocity = 0 }
        }
    }

    /// Offset that places the nearest script line on the reading guide.
    func nearestCenteredOffset(lineHeight: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let upper = max(0, maxOffset)
        guard lineHeight > 0 else { return min(max(0, offset), upper) }
        let snapped = (offset / lineHeight).rounded() * lineHeight
        return min(max(0, snapped), upper)
    }

    /// Estimated line height for the Prompter font at `fontSize`.
    static func estimatedLineHeight(fontSize: CGFloat) -> CGFloat {
        max(1, fontSize * 1.22)
    }

    // MARK: - Private Helpers

    private mutating func integrateMomentum(deltaTime dt: CGFloat) {
        guard abs(velocity) > Self.settleVelocity else {
            velocity = 0
            return
        }
        offset += velocity * dt
        velocity *= exp(-Self.momentumFriction * dt)
        // Below the settle speed the coast is over; leave nothing behind for a
        // ticker that is about to stop.
        if abs(velocity) <= Self.settleVelocity { velocity = 0 }
    }

    private mutating func applySnap(
        deltaTime dt: CGFloat,
        lineHeight: CGFloat,
        maxOffset: CGFloat,
        scrubDetent: Bool
    ) {
        guard lineHeight > 0 else { return }
        let spring: CGFloat
        if isSettling {
            spring = Self.snapSpring
        } else if scrubDetent {
            spring = Self.scrubSnapSpring
        } else {
            return
        }
        let target = nearestCenteredOffset(lineHeight: lineHeight, maxOffset: maxOffset)
        offset += (target - offset) * min(1, spring * dt)
        if isSettling,
           abs(target - offset) <= Self.settleDistance,
           abs(velocity) < Self.settleVelocity {
            offset = target
            velocity = 0
            isSettling = false
        }
    }
}
