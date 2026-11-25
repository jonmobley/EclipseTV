//
//  TVSlideshowPlayer.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Runs a slideshow on the TV by itself: shows a slide, waits, shows the next.
///
/// The phone sends the whole slideshow once (`play_slideshow`); from then on this
/// player keeps time, so slides change on the TV even if the phone is busy or
/// briefly disconnected. A step from the phone (`slideshow_control` goto) jumps to
/// that slide and restarts the wait. Anything else the phone puts on screen stops it.
///
/// Thread Safety: Main actor only (drives UIKit through `presentSlide`).
@MainActor
final class TVSlideshowPlayer {

    // MARK: - Properties

    /// Shows a slide. Returns false when the TV can no longer show it.
    /// The second value asks for a dissolve (true) or a cut (false).
    var presentSlide: ((_ id: String, _ crossfade: Bool) -> Bool)?

    /// The running slideshow, nil when stopped.
    private(set) var plan: TVSlideshowPlan?

    /// Fires the next advance. Replaced in tests to drive time by hand.
    var scheduleTimer: (TimeInterval, @escaping () -> Void) -> Timer? = { seconds, fire in
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in fire() }
        }
    }

    private var timer: Timer?

    // MARK: - Public Interface

    /// Whether a slideshow is running.
    var isRunning: Bool { plan != nil }

    /// Starts `newPlan` on its start slide (dissolving in when it crossfades).
    /// - Parameter newPlan: The slideshow to run; replaces any running one.
    func start(_ newPlan: TVSlideshowPlan) {
        stop()
        plan = newPlan
        showCurrentOrSkip(crossfade: newPlan.crossfades)
    }

    /// Jumps to slide `id` and restarts the slide timer.
    /// - Parameter id: A slide id from the running slideshow.
    /// - Returns: false when nothing runs or `id` is not one of its slides.
    @discardableResult
    func goTo(id: String) -> Bool {
        guard let next = plan?.jumped(toId: id) else { return false }
        plan = next
        showCurrentOrSkip(crossfade: next.crossfades)
        return true
    }

    /// Stops advancing. The slide on screen stays.
    func stop() {
        timer?.invalidate()
        timer = nil
        plan = nil
    }

    /// Moves on as if the slide timer fired. Internal so tests can call it.
    func timerFired() {
        guard let current = plan else { return }
        guard let next = current.advanced() else {
            // End of a slideshow that doesn't loop: the last slide stays.
            stop()
            return
        }
        plan = next
        showCurrentOrSkip(crossfade: next.crossfades)
    }

    // MARK: - Private Helpers

    /// Shows the current slide; drops slides the TV lost until one shows.
    private func showCurrentOrSkip(crossfade: Bool) {
        while let current = plan {
            if presentSlide?(current.currentId, crossfade) ?? false {
                restartTimer()
                return
            }
            plan = current.removing(id: current.currentId)
        }
        stop()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard let current = plan, current.autoAdvances, let seconds = current.seconds else {
            return
        }
        timer = scheduleTimer(seconds) { [weak self] in
            self?.timerFired()
        }
    }
}

// MARK: - Which messages stop a slideshow

/// Decides which phone messages end a TV-run slideshow.
///
/// Anything that puts something else on screen (or blanks it) stops it.
/// Settings, library edits and unknown messages from newer phones do not.
/// Thread Safety: Pure; safe from any thread.
enum TVSlideshowInterruption {

    /// Whether a message of `kind` stops a running slideshow.
    /// - Parameter kind: The decoded message kind; nil for kinds this TV doesn't know.
    /// - Returns: `true` when the slideshow should stop before the message is applied.
    static func stops(_ kind: EclipseShareProtocol.Kind?) -> Bool {
        switch kind {
        case .playRequest, .setIdleMode, .setDisplayMode:
            return true
        default:
            return false
        }
    }
}
