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

    /// Posted once each time the clock runs down to zero on its own.
    ///
    /// Separate from `didChangeNotification` because `remaining == 0` is a state the
    /// UI reads on every tick, while the end action must run exactly once. A manual
    /// pause landing on zero is not an expiry and does not post.
    static let didExpireNotification = Notification.Name(
        "CountdownController.didExpire"
    )

    /// ⋯ menu duration presets, shortest first.
    nonisolated static let durationPresets: [Int] = [30, 60, 120, 300, 600]

    nonisolated static let defaultDuration = 300

    private let defaults: UserDefaults
    private let now: () -> Date
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

    /// The moment the clock actually reached zero, or nil if it hasn't since the
    /// last start. Taken from the deadline, not from when the tick noticed.
    private(set) var expiredAt: Date?

    /// Creates a controller; tests pass an isolated defaults suite and a clock they
    /// can advance, so crossing zero is not tied to wall-clock sleeps.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
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

    deinit {
        timer?.invalidate()
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
        expiredAt = nil
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
        expiredAt = nil
        deadline = now().addingTimeInterval(TimeInterval(remaining))
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
        expiredAt = nil
        notify()
    }

    /// Sets length, resets remaining, and keeps running if it was.
    func setDuration(_ seconds: Int) {
        let next = Self.clampedDuration(seconds)
        duration = next
        remaining = next
        expiredAt = nil
        defaults.set(next, forKey: Self.durationKey)
        if running {
            deadline = now().addingTimeInterval(TimeInterval(next))
        }
        if let liveCountdownId {
            CountdownStore.shared.setDuration(id: liveCountdownId, seconds: next)
        }
        notify()
    }

    /// How long ago the clock hit zero, or nil when it hasn't since the last start.
    var secondsSinceExpiry: TimeInterval? {
        expiredAt.map { now().timeIntervalSince($0) }
    }

    /// Recomputes remaining from `deadline`. Tests call this instead of waiting.
    ///
    /// - Returns: `true` when this call is the one that crossed zero. Clearing
    ///   `running` and `deadline` here is what keeps that true only once.
    @discardableResult
    func syncRemainingFromDeadline() -> Bool {
        guard running, let deadline else { return false }
        remaining = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        guard remaining == 0 else { return false }
        running = false
        expiredAt = deadline
        self.deadline = nil
        timer?.invalidate()
        timer = nil
        return true
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
        let didExpire = syncRemainingFromDeadline()
        if remaining != previous || running != wasRunning {
            notify()
        }
        // Posted after `notify()` so output paints red 0:00 before any end action.
        if didExpire {
            NotificationCenter.default.post(
                name: Self.didExpireNotification,
                object: self
            )
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

}
