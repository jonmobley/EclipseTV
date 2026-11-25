//
//  CountdownClockSettings+Text.swift
//  Eclipse
//
//  Words for To Time targets and idle tiles ("to 6:30 PM", "Count Up").
//  Thread Safety: Pure functions on value types, safe from any thread.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Target Text

extension CountdownClockSettings {

    /// The target as words, e.g. `6:30 PM` or `Dec 24, 6:30 PM`, plus the
    /// zone's short name when a zone other than the device's was chosen.
    /// - Parameter now: Supplies "today" when no day is pinned.
    /// - Returns: Nil when no target time is set.
    func targetText(now: Date = Date()) -> String? {
        guard let target = targetDate(relativeTo: now) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = resolvedTimeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(
            targetDay.isEmpty ? "jmm" : "MMMdjmm"
        )
        var text = formatter.string(from: target)
        if let zone = zoneShortName(at: target) {
            text += " \(zone)"
        }
        return text
    }

    /// Short name of a named zone that differs from the device's (e.g. `EST`).
    /// - Parameter date: Moment the name is taken at (daylight time changes it).
    /// - Returns: Nil when the clock reads in the device's own zone.
    func zoneShortName(at date: Date = Date()) -> String? {
        guard !targetTimeZone.isEmpty,
              let zone = TimeZone(identifier: targetTimeZone),
              zone.secondsFromGMT(for: date) != TimeZone.current.secondsFromGMT(for: date)
        else { return nil }
        return zone.abbreviation(for: date) ?? zone.identifier
    }

    /// Readable zone line for the editor, e.g. `America/New_York (EST)`.
    var zoneDescription: String? {
        guard !targetTimeZone.isEmpty else { return nil }
        guard let zone = TimeZone(identifier: targetTimeZone) else { return targetTimeZone }
        let city = zone.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        let short = zone.abbreviation() ?? ""
        return short.isEmpty ? city : "\(city) (\(short))"
    }

    /// Next whole hour after `now`, as minutes after midnight in the device zone.
    ///
    /// The starting value when someone first picks To Time.
    static func defaultTargetMinutes(after now: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.hour], from: now)
        return (((parts.hour ?? 0) + 1) % 24) * 60
    }
}

// MARK: - Idle Face

extension CountdownClockSettings {

    /// What an idle tile shows for this clock.
    /// - Parameters:
    ///   - duration: The tile's countdown length.
    ///   - held: Seconds held from an earlier run, if any.
    ///   - now: Supplies "today" for To Time.
    /// - Returns: `5:00` / `0:00` / held time, or `to 6:30 PM` for To Time.
    func idleFaceText(duration: Int, held: Int?, now: Date = Date()) -> String {
        switch mode {
        case .countdown:
            return CountdownController.displayString(seconds: held ?? duration)
        case .countUp:
            return CountdownController.displayString(seconds: held ?? 0)
        case .timeOfDay:
            guard let target = targetText(now: now) else { return "To Time" }
            return "to \(target)"
        }
    }
}
