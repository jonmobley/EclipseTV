//
//  CountdownController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Session clock for the live Show Countdown tile.
///
/// Runs in the live countdown's mode: Countdown (down from `duration`), Count Up
/// (up from 0:00, never ends) or To Time (down to a clock time). `remaining` is
/// always the seconds on the face, so for Count Up it is the elapsed time.
/// Main-actor only.
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

    /// A part-used clock kept for a countdown that is no longer on output.
    ///
    /// The length it was counting is stored beside the remainder so editing the
    /// tile's duration invalidates the hold instead of resuming against a length
    /// the user has since changed.
    private struct HeldClock {
        var remaining: Int
        var duration: Int
        var mode: CountdownMode
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private var timer: Timer?
    /// Deadline (Countdown, To Time) or virtual start (Count Up) of the running face.
    private var deadline: Date?

    /// Part-used clocks by countdown id, so cutting away to a video and back
    /// resumes rather than starting over. Session-only: a relaunch starts fresh.
    private var heldClocks: [UUID: HeldClock] = [:]

    /// Countdown whose clock is on AirPlay / HDMI / Practice, if any.
    private(set) var liveCountdownId: UUID?

    /// Last chosen length; remaining resets to this on Reset / preset.
    private(set) var duration: Int

    /// Seconds on the face: left for Countdown / To Time, elapsed for Count Up.
    private(set) var remaining: Int

    /// Mode and To Time target of the live countdown (caption / plate ride along).
    private(set) var clockSettings = CountdownClockSettings()

    /// How the live clock counts.
    var mode: CountdownMode { clockSettings.mode }

    /// True when the face shows a spent clock (red 0:00); never for Count Up.
    var isAtEnd: Bool { mode.expires && remaining == 0 }

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

    // MARK: - Going Live

    /// Binds the clock to `item` without announcing it, resuming a held remainder
    /// if any.
    ///
    /// Going live publishes the overlay between this and `start()`. Announcing the
    /// bind first repainted the Show grid from the *previous* program, and while a
    /// countdown was already live that repaint was the last one the tiles got —
    /// `refreshCountdownChrome` deliberately skips the grid once the clock owns
    /// output, so the outgoing timer kept the blue stroke and the incoming one never
    /// took it.
    func prepare(_ item: ShowCountdown) {
        // Read before holding, so re-binding the countdown already on output
        // cannot resume from the remainder that hold is about to file for it.
        let resumed = heldRemaining(for: item)
        holdOutgoingClock()
        heldClocks[item.id] = nil
        liveCountdownId = item.id
        clockSettings = item.clock
        applyDuration(item.duration, notifying: false)
        remaining = resumed ?? item.clock.restingSeconds(duration: duration, now: now())
        expiredAt = nil
    }

    /// Takes a new mode, target, caption or plate for the live countdown.
    ///
    /// A change in how it counts resets the face (and keeps it running if it
    /// was); a caption or plate change only repaints.
    func adoptClock(_ settings: CountdownClockSettings) {
        guard settings != clockSettings else { return }
        let countsSame = settings.countsLike(clockSettings)
        clockSettings = settings
        guard !countsSame else {
            notify()
            return
        }
        let wasRunning = running
        stopKeepingRemaining()
        remaining = settings.restingSeconds(duration: duration, now: now())
        expiredAt = nil
        if wasRunning {
            start()
        } else {
            notify()
        }
    }

    /// Binds, resumes any held remainder, and starts — for tests and callers that
    /// do not need the silent prepare / overlay / start split.
    func present(_ item: ShowCountdown) {
        prepare(item)
        start()
    }

    /// Clears the live id and pauses, keeping any remainder for a later tap.
    func endLive() {
        holdOutgoingClock()
        liveCountdownId = nil
        expiredAt = nil
        notify()
    }

    /// Seconds a tap on `item` would resume from, or nil when it would start over.
    ///
    /// Tiles read this so the number on the card is the number a tap produces.
    func heldRemaining(for item: ShowCountdown) -> Int? {
        guard let held = heldClocks[item.id], held.mode == item.clock.mode,
              held.remaining > 0 else { return nil }
        switch held.mode {
        case .countdown:
            guard held.duration == Self.clampedDuration(item.duration),
                  held.remaining < held.duration else { return nil }
            return held.remaining
        case .countUp:
            return held.remaining
        case .timeOfDay:
            return nil
        }
    }

    /// Seconds a tap on `item` would put on the clock.
    func startSeconds(for item: ShowCountdown) -> Int {
        heldRemaining(for: item)
            ?? item.clock.restingSeconds(duration: item.duration, now: now())
    }

    /// Drops any remainder held for `id` so the next tap starts over.
    func discardHeldTime(for id: UUID) {
        guard heldClocks.removeValue(forKey: id) != nil else { return }
        notify()
    }

    // MARK: - Clock

    /// Starts from remaining (a spent countdown starts over from `duration`).
    ///
    /// To Time always re-reads the target, so a resume jumps to the true time
    /// left; one whose target has passed stays on 0:00 without running.
    func start() {
        switch mode {
        case .countdown where remaining <= 0:
            remaining = duration
        case .timeOfDay:
            remaining = clockSettings.restingSeconds(duration: duration, now: now())
        default:
            break
        }
        expiredAt = nil
        guard !isAtEnd else {
            notify()
            return
        }
        deadline = clockSettings.anchor(face: remaining, now: now())
        running = true
        installTimer()
        notify()
    }

    /// Holds remaining without clearing it.
    func pause() {
        guard running else { return }
        stopKeepingRemaining()
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

    /// Restores the resting face (length, 0:00, or time to target) and stops.
    func reset() {
        pause()
        remaining = clockSettings.restingSeconds(duration: duration, now: now())
        expiredAt = nil
        notify()
    }

    /// Sets length, resets remaining, and keeps running if it was.
    func setDuration(_ seconds: Int) {
        applyDuration(seconds, notifying: true)
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
        remaining = clockSettings.face(anchor: deadline, now: now())
        guard isAtEnd else { return false }
        running = false
        expiredAt = deadline
        self.deadline = nil
        timer?.invalidate()
        timer = nil
        return true
    }

    // MARK: - Private

    /// Duration write shared with `prepare(_:)`, which skips the notification so
    /// the overlay can publish before anything observing the clock repaints.
    ///
    /// Only a Countdown's face follows the length; Count Up and To Time keep theirs.
    private func applyDuration(_ seconds: Int, notifying: Bool) {
        let next = Self.clampedDuration(seconds)
        duration = next
        defaults.set(next, forKey: Self.durationKey)
        if mode == .countdown {
            remaining = next
            expiredAt = nil
            if running {
                deadline = now().addingTimeInterval(TimeInterval(next))
            }
        }
        if let liveCountdownId {
            CountdownStore.shared.setDuration(id: liveCountdownId, seconds: next)
        }
        guard notifying else { return }
        notify()
    }

    /// Stops the clock leaving output and files any part-used remainder under its id.
    ///
    /// Countdown → countdown does not reach overlay teardown, because the overlay
    /// kind is unchanged and `ExternalDisplayManager` has nothing to end, so
    /// `prepare(_:)` holds the outgoing clock here as well as `endLive()`.
    /// A countdown at zero or still at full length, a Count Up still at 0:00 and
    /// any To Time clock (it re-reads its target) have nothing worth keeping.
    private func holdOutgoingClock() {
        let outgoing = liveCountdownId
        stopKeepingRemaining()
        guard let outgoing, remaining > 0 else { return }
        switch mode {
        case .countdown where remaining < duration, .countUp:
            heldClocks[outgoing] = HeldClock(
                remaining: remaining, duration: duration, mode: mode
            )
        default:
            return
        }
    }

    /// `pause()` without the notification, for callers that post their own.
    private func stopKeepingRemaining() {
        guard running else { return }
        syncRemainingFromDeadline()
        running = false
        deadline = nil
        timer?.invalidate()
        timer = nil
    }

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
