//
//  CountdownController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Session clock for the live Show Countdown tile.
@MainActor
final class CountdownController {

    static let shared = CountdownController()

    nonisolated static let durationKey = "EclipseTV.countdown.duration"

    /// Posted when remaining time, duration, or running state changes.
    static let didChangeNotification = Notification.Name(
        "CountdownController.didChange"
    )

    /// Ribbon / ⋯ duration chips, shortest first.
    nonisolated static let durationPresets: [Int] = [30, 60, 120, 300, 600]

    nonisolated static let defaultDuration = 300

    private let defaults: UserDefaults
    private var timer: Timer?
    private var deadline: Date?

    /// Countdown whose clock is on AirPlay / HDMI / Practice, if any.
    private(set) var liveCountdownId: UUID?

    /// Last chosen length; remaining resets to this on Reset / preset.
    private(set) var duration: Int

    /// Seconds still on the clock.
    private(set) var remaining: Int

    /// True while the clock is counting toward zero.
    private(set) var running = false

    /// Creates a controller; tests pass an isolated defaults suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        duration = Self.lastStoredDuration(defaults: defaults)
        remaining = duration
    }

    /// Last duration written to `defaults`, or five minutes.
    nonisolated static func lastStoredDuration(
        defaults: UserDefaults = .standard
    ) -> Int {
        let stored = defaults.integer(forKey: durationKey)
        return stored > 0 ? clampedDuration(stored) : defaultDuration
    }

    /// Clamps to 1 second…24 hours.
    nonisolated static func clampedDuration(_ seconds: Int) -> Int {
        min(max(seconds, 1), 24 * 60 * 60)
    }

    deinit {
        timer?.invalidate()
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

    /// True when `duration` is one of the ribbon presets.
    var isPresetDuration: Bool {
        Self.durationPresets.contains(duration)
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

    /// Tile caption: live name plus remaining time.
    var tileTitle: String {
        let name = liveCountdownId.flatMap {
            CountdownStore.shared.countdown(id: $0)?.name
        } ?? "Countdown"
        return "\(name)\n\(displayString)"
    }

    /// Binds the clock to `item` and starts from its duration.
    func present(_ item: ShowCountdown) {
        liveCountdownId = item.id
        setDuration(item.duration)
        start()
    }

    /// Clears the live id and pauses (overlay teardown).
    func endLive() {
        liveCountdownId = nil
        if running {
            pause()
        } else {
            notify()
        }
    }

    /// Starts from remaining, or from `duration` when already at zero.
    func start() {
        if remaining <= 0 {
            remaining = duration
        }
        deadline = Date().addingTimeInterval(TimeInterval(remaining))
        running = true
        installTimer()
        notify()
    }

    /// Holds remaining without clearing it.
    func pause() {
        guard running else { return }
        syncRemainingFromDeadline()
        running = false
        deadline = nil
        timer?.invalidate()
        timer = nil
        notify()
    }

    /// Pause if running, otherwise start.
    func toggleRunning() {
        if running {
            pause()
        } else {
            start()
        }
    }

    /// Restores remaining to `duration` and stops.
    func reset() {
        pause()
        remaining = duration
        notify()
    }

    /// Sets length, resets remaining, and keeps running if it was.
    func setDuration(_ seconds: Int) {
        let next = Self.clampedDuration(seconds)
        duration = next
        remaining = next
        defaults.set(next, forKey: Self.durationKey)
        if running {
            deadline = Date().addingTimeInterval(TimeInterval(next))
        }
        if let liveCountdownId {
            CountdownStore.shared.setDuration(id: liveCountdownId, seconds: next)
        }
        notify()
    }

    /// Recomputes remaining from `deadline`. Tests call this instead of waiting.
    func syncRemainingFromDeadline() {
        guard running, let deadline else { return }
        remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        if remaining == 0 {
            running = false
            self.deadline = nil
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Private

    private func installTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handleTick() {
        let wasRunning = running
        let previous = remaining
        syncRemainingFromDeadline()
        guard remaining != previous || running != wasRunning else { return }
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

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
