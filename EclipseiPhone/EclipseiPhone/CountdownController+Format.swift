//
//  CountdownController+Format.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Duration Formatting and Parsing

extension CountdownController {

    /// Clamps to 1 second…24 hours.
    nonisolated static func clampedDuration(_ seconds: Int) -> Int {
        min(max(seconds, 1), 24 * 60 * 60)
    }

    /// `M:SS` under an hour, otherwise `H:MM:SS`.
    nonisolated static func displayString(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Current remaining, formatted for tiles and the live hero.
    var displayString: String {
        Self.displayString(seconds: remaining)
    }

    /// True when `duration` is one of the menu presets.
    var isPresetDuration: Bool {
        Self.durationPresets.contains(duration)
    }

    /// Tile caption: live name plus remaining time.
    var tileTitle: String {
        let name = liveCountdownId.flatMap {
            CountdownStore.shared.countdown(id: $0)?.name
        } ?? "Countdown"
        return "\(name)\n\(displayString)"
    }

    /// Minutes (`7` → 7:00), `m:ss`, or `h:mm:ss`. Nil when empty or invalid.
    nonisolated static func parseDuration(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard (1...3).contains(parts.count) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        guard let seconds = seconds(fromComponents: values), seconds >= 1 else {
            return nil
        }
        return clampedDuration(seconds)
    }

    // MARK: - Private

    nonisolated private static func seconds(fromComponents values: [Int]) -> Int? {
        switch values.count {
        case 1:
            guard values[0] >= 0 else { return nil }
            return values[0] * 60
        case 2:
            let minutes = values[0]
            let secs = values[1]
            guard minutes >= 0, secs >= 0, secs < 60 else { return nil }
            return minutes * 60 + secs
        case 3:
            let hours = values[0]
            let minutes = values[1]
            let secs = values[2]
            guard hours >= 0, minutes >= 0, minutes < 60,
                  secs >= 0, secs < 60 else { return nil }
            return hours * 3600 + minutes * 60 + secs
        default:
            return nil
        }
    }
}
