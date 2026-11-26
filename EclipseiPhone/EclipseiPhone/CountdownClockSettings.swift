//
//  CountdownClockSettings.swift
//  Eclipse
//
//  How a Countdown tile counts (down, up, or to a clock time) and how its face
//  looks (caption, plate). Mirrors the Mac's timer options and syncs through the
//  `Countdown` iCloud record (`mode`, `targetMinutes`, `targetDay`,
//  `targetTimeZone`, `caption`, `style`).
//  Thread Safety: Plain value types, safe from any thread.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Mode

/// How a countdown derives the number on its face.
enum CountdownMode: String, Codable, CaseIterable, Hashable {
    /// Counts down from the tile's duration to 0:00.
    case countdown
    /// Starts at 0:00 and counts up until paused; never ends on its own.
    case countUp
    /// Counts down to a time of day, optionally on a date and in a named zone.
    case timeOfDay

    /// Menu and row title; same words as the Mac.
    var title: String {
        switch self {
        case .countdown: return "Countdown"
        case .countUp: return "Count Up"
        case .timeOfDay: return "To Time"
        }
    }

    /// One-line explanation shown under the mode choice.
    var explanation: String {
        switch self {
        case .countdown: return "Counts down from a set length."
        case .countUp: return "Starts at zero and counts up until you pause."
        case .timeOfDay: return "Counts down to a clock time, date, and zone."
        }
    }

    /// SF Symbol for rows and menus.
    var systemImage: String {
        switch self {
        case .countdown: return "timer"
        case .countUp: return "stopwatch"
        case .timeOfDay: return "clock"
        }
    }

    /// Whether the clock stops at 0:00 and runs the end action.
    var expires: Bool { self != .countUp }
}

// MARK: - Plate Style

/// What sits behind the digits on output.
enum CountdownPlateStyle: String, Codable, CaseIterable, Hashable {
    /// Dark rounded plate behind the digits and caption ("Card behind numbers").
    case card
    /// Digits and caption only.
    case simple
}

// MARK: - Settings

/// Mode, To Time target, caption and plate for one countdown.
///
/// Every field has a default so countdowns saved or synced before these options
/// existed read as a plain countdown with a plate and no caption, like the Mac.
struct CountdownClockSettings: Codable, Equatable, Hashable {
    /// Minutes in a day; the exclusive bound of `targetMinutes`.
    static let minutesPerDay = 24 * 60
    /// Caption length cap, same as names and the Mac's synced caption.
    static let maxCaptionLength = UserDisplayName.maxLength

    var mode: CountdownMode
    /// To Time target as minutes after midnight (0…1439); nil until chosen.
    var targetMinutes: Int?
    /// To Time day as `yyyy-MM-dd`; empty means today's occurrence.
    var targetDay: String
    /// IANA zone id for To Time; empty means the device's current zone.
    var targetTimeZone: String
    /// Short words above the digits; empty shows none.
    var caption: String
    var style: CountdownPlateStyle

    /// Creates settings; the defaults are a plain countdown with a plate.
    init(
        mode: CountdownMode = .countdown,
        targetMinutes: Int? = nil,
        targetDay: String = "",
        targetTimeZone: String = "",
        caption: String = "",
        style: CountdownPlateStyle = .card
    ) {
        self.mode = mode
        self.targetMinutes = targetMinutes.map(Self.clampedMinutes)
        self.targetDay = targetDay
        self.targetTimeZone = targetTimeZone
        self.caption = Self.clampedCaption(caption)
        self.style = style
    }

    /// Whether the plate is drawn behind the digits.
    var showsPlate: Bool { style == .card }

    /// True when mode and To Time target match, ignoring caption and plate.
    func countsLike(_ other: CountdownClockSettings) -> Bool {
        mode == other.mode && targetMinutes == other.targetMinutes
            && targetDay == other.targetDay && targetTimeZone == other.targetTimeZone
    }

    /// Copies the To Time target (time, day, zone) from `other`.
    mutating func takeTarget(from other: CountdownClockSettings) {
        targetMinutes = other.targetMinutes
        targetDay = other.targetDay
        targetTimeZone = other.targetTimeZone
    }

    /// Keeps minutes inside one day.
    static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), minutesPerDay - 1)
    }

    /// Trims whitespace and caps the length; empty means no caption.
    static func clampedCaption(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxCaptionLength))
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case mode, targetMinutes, targetDay, targetTimeZone, caption, style
    }

    /// Decodes leniently: missing or unknown values fall back to the defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = (try? c.decodeIfPresent(String.self, forKey: .mode))
            .flatMap { $0 }.flatMap(CountdownMode.init(rawValue:))
        let style = (try? c.decodeIfPresent(String.self, forKey: .style))
            .flatMap { $0 }.flatMap(CountdownPlateStyle.init(rawValue:))
        self.init(
            mode: mode ?? .countdown,
            targetMinutes: try c.decodeIfPresent(Int.self, forKey: .targetMinutes),
            targetDay: try c.decodeIfPresent(String.self, forKey: .targetDay) ?? "",
            targetTimeZone: try c.decodeIfPresent(String.self, forKey: .targetTimeZone) ?? "",
            caption: try c.decodeIfPresent(String.self, forKey: .caption) ?? "",
            style: style ?? .card
        )
    }
}
