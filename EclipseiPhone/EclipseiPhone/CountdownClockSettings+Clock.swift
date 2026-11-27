//
//  CountdownClockSettings+Clock.swift
//  Eclipse
//
//  To Time target math (same semantics as the Mac's `SyncCountdown`) and the
//  per-mode rules the live clock uses to turn wall time into face seconds.
//  Thread Safety: Pure functions on value types, safe from any thread.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - To Time Target

extension CountdownClockSettings {

    /// The absolute moment of the To Time target.
    ///
    /// Without a day the target is today's occurrence in the target zone; it does
    /// not roll to tomorrow once passed (matching the Mac).
    /// - Parameter now: Supplies "today" when no day is pinned.
    /// - Returns: The target instant, or nil when no target time is set.
    func targetDate(relativeTo now: Date) -> Date? {
        guard let targetMinutes else { return nil }
        let calendar = Self.calendar(in: targetTimeZone)
        var parts = Self.dayParts(targetDay)
            ?? calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = targetMinutes / 60
        parts.minute = targetMinutes % 60
        parts.second = 0
        return calendar.date(from: parts)
    }

    /// Whole seconds from `now` until the target, never below zero.
    /// - Parameter now: The moment to measure from.
    /// - Returns: Seconds remaining, or nil when no target time is set.
    func secondsUntilTarget(now: Date) -> Int? {
        guard let target = targetDate(relativeTo: now) else { return nil }
        return max(0, Int(target.timeIntervalSince(now).rounded(.up)))
    }

    /// The zone the target is read in: the named one, else the device's.
    var resolvedTimeZone: TimeZone {
        Self.zone(targetTimeZone)
    }

    /// `yyyy-MM-dd` for a calendar day.
    static func dayString(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Year, month and day from `yyyy-MM-dd`, or nil when blank or malformed.
    static func dayParts(_ day: String) -> DateComponents? {
        guard !day.isEmpty else { return nil }
        let numbers = day.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3, (1...12).contains(numbers[1]),
              (1...31).contains(numbers[2]) else { return nil }
        return DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])
    }

    /// The named zone, or the device's current zone when blank or unknown.
    static func zone(_ identifier: String) -> TimeZone {
        guard !identifier.isEmpty, let zone = TimeZone(identifier: identifier) else {
            return .current
        }
        return zone
    }

    /// Gregorian calendar in the given zone id (blank = device zone).
    static func calendar(in zoneId: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone(zoneId)
        return calendar
    }
}

// MARK: - Live Clock Rules

extension CountdownClockSettings {

    /// Face seconds after Reset or a fresh start.
    /// - Parameters:
    ///   - duration: The tile's countdown length.
    ///   - now: Current time, for To Time.
    /// - Returns: Duration, zero, or seconds until the target.
    func restingSeconds(duration: Int, now: Date) -> Int {
        switch mode {
        case .countdown: return duration
        case .countUp: return 0
        case .timeOfDay: return secondsUntilTarget(now: now) ?? 0
        }
    }

    /// The moment a running face is measured against.
    ///
    /// A deadline for Countdown and To Time, the (virtual) start for Count Up.
    /// - Parameters:
    ///   - face: Seconds currently on the face.
    ///   - now: Current time.
    /// - Returns: The anchor to pass to `face(anchor:now:)` on each tick.
    func anchor(face: Int, now: Date) -> Date {
        switch mode {
        case .countdown:
            return now.addingTimeInterval(TimeInterval(face))
        case .countUp:
            return now.addingTimeInterval(-TimeInterval(face))
        case .timeOfDay:
            return targetDate(relativeTo: now) ?? now
        }
    }

    /// Face seconds at `now` for a clock running against `anchor`.
    /// - Parameters:
    ///   - anchor: Value from `anchor(face:now:)`.
    ///   - now: Current time.
    /// - Returns: Whole seconds, never below zero.
    func face(anchor: Date, now: Date) -> Int {
        switch mode {
        case .countUp:
            return max(0, Int(floor(now.timeIntervalSince(anchor))))
        case .countdown, .timeOfDay:
            return max(0, Int(ceil(anchor.timeIntervalSince(now))))
        }
    }
}
