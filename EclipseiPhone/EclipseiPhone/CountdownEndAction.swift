//
//  CountdownEndAction.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// What output does when a countdown reaches 0:00.
///
/// Stored per countdown rather than as one app setting: a Show routinely holds a
/// pre-service timer that should roll into the opener and an offering timer that
/// should just sit there, and those want opposite endings.
enum CountdownEndAction: String, CaseIterable, Codable, Equatable, Hashable {
    /// Leave the red 0:00 clock on output until someone changes it.
    case hold
    /// Drop the clock and blank the display.
    case black
    /// Go live with the next item in this Show's order.
    case next

    /// What existing countdowns do, and what an unreadable token degrades to.
    static let fallback = CountdownEndAction.hold

    /// How late the action may still run after the true zero moment.
    ///
    /// The clock is deadline-based, so a phone that slept through zero reports the
    /// expiry the instant it wakes. Switching output minutes late would yank the
    /// room off whatever the operator put up in the meantime, so a stale expiry
    /// holds instead of acting.
    static let maximumLateness: TimeInterval = 30

    /// ⋯ menu title.
    var title: String {
        switch self {
        case .hold: return "Hold at 0:00"
        case .black: return "Go Black"
        case .next: return "Play Next in Show"
        }
    }

    /// ⋯ menu glyph.
    var systemImage: String {
        switch self {
        case .hold: return "pause.rectangle"
        case .black: return "rectangle.slash"
        case .next: return "forward.end.alt"
        }
    }

    /// Round-trip token for JSON and CloudKit.
    var token: String { rawValue }

    /// Parses `token`, falling back to `.hold` for anything unrecognized.
    ///
    /// A newer build's token must degrade to the old do-nothing behavior rather
    /// than fail the whole countdown decode.
    init(token: String?) {
        guard let token, let action = CountdownEndAction(rawValue: token) else {
            self = Self.fallback
            return
        }
        self = action
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        self.init(token: token)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}
