//
//  CountdownEndDecision.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Whether a countdown's end action may take over output at 0:00.
///
/// Each refusal is a case where the phone knows the time but not the room: a
/// remote operator's clock mirrors output it does not own, a locked output has
/// promised the room nothing will change, and a clock that ran out while the
/// phone slept is reporting old news.
enum CountdownEndDecision: Equatable {
    /// Take over output.
    case run
    /// Leave the red 0:00 clock alone.
    case hold

    /// Decides whether to run the end action.
    ///
    /// - Parameters:
    ///   - action: The countdown's configured ending.
    ///   - isCountdownLive: The clock is the live overlay on this device.
    ///   - isRemoteOperator: This device drives another phone's output.
    ///   - isOutputLocked: The operator pinned live output in place.
    ///   - secondsSinceExpiry: Age of the expiry, measured from the true zero
    ///     moment rather than from when a tick noticed it. Nil when the clock
    ///     has not run out since its last start.
    static func decide(
        action: CountdownEndAction,
        isCountdownLive: Bool,
        isRemoteOperator: Bool,
        isOutputLocked: Bool,
        secondsSinceExpiry: TimeInterval?
    ) -> CountdownEndDecision {
        guard action != .hold else { return .hold }
        guard isCountdownLive, !isRemoteOperator, !isOutputLocked else { return .hold }
        guard let age = secondsSinceExpiry,
              age <= CountdownEndAction.maximumLateness
        else { return .hold }
        return .run
    }
}
