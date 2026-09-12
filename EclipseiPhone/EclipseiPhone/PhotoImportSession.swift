//
//  PhotoImportSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// State of one in-flight Photos import: how far the iCloud downloads have got,
/// and whether the user has called them off.
///
/// The session follows the `Progress` object each `NSItemProvider` load returns
/// and folds them into a single fraction, so a batch reads as one bar rather than
/// several. It owns no views; the host controller renders `onChange`.
///
/// Nothing appears immediately. Most picks are already on the device and finish in
/// milliseconds, so revealing chrome for them would be a flash of noise — the
/// session only marks itself visible once the work outlives `revealDelay`.
@MainActor
final class PhotoImportSession {

    /// How long the work must last before the overlay is worth showing.
    static let revealDelay: Duration = .milliseconds(350)

    /// Picks in the batch.
    private(set) var total = 0
    /// Picks that have finished, whatever their outcome.
    private(set) var completed = 0
    /// Combined download progress across the batch, 0…1.
    private(set) var fraction: Double = 0
    /// True once the user has asked to stop.
    private(set) var isCancelled = false
    /// True while the overlay should be on screen.
    private(set) var isVisible = false

    /// Called on every change worth re-rendering.
    var onChange: (() -> Void)?

    private var isRunning = false
    private var revealTask: Task<Void, Never>?
    private var observations: [Int: NSKeyValueObservation] = [:]
    private var live: [Int: Progress] = [:]
    private var fractions: [Int: Double] = [:]

    // MARK: - Lifecycle

    /// Starts tracking a batch of `total` picks.
    func begin(total: Int) {
        end()
        self.total = max(total, 0)
        completed = 0
        fraction = 0
        isCancelled = false
        isRunning = self.total > 0
        guard isRunning else { return }
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: Self.revealDelay)
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.isVisible = true
            self.onChange?()
        }
        onChange?()
    }

    /// Stops tracking. Downloads still in flight are left alone — call `cancel()`
    /// first to actually stop them.
    func end() {
        revealTask?.cancel()
        revealTask = nil
        isRunning = false
        isVisible = false
        stopObserving()
        total = 0
        completed = 0
        fraction = 0
        fractions = [:]
        onChange?()
    }

    // MARK: - Per-pick tracking

    /// Follows one pick's download.
    ///
    /// A pick that starts after the user cancelled is stopped immediately, which
    /// is how the tail of a batch unwinds without a per-item check at every step.
    func track(_ progress: Progress, at index: Int) {
        guard isRunning else { return }
        guard !isCancelled else {
            progress.cancel()
            return
        }
        live[index] = progress
        observations[index] = progress.observe(
            \.fractionCompleted, options: [.initial, .new]
        ) { [weak self] observed, _ in
            let value = observed.fractionCompleted
            Task { @MainActor in
                self?.report(fraction: value, at: index)
            }
        }
    }

    /// Records a download fraction for one pick.
    ///
    /// Only increases are accepted: KVO notifications arrive off the main actor
    /// and are re-dispatched, so two updates can land out of order, and a bar that
    /// slides backwards reads as a stall.
    func report(fraction value: Double, at index: Int) {
        guard isRunning, live[index] != nil else { return }
        let clamped = min(max(value, 0), 1)
        guard clamped > (fractions[index] ?? 0) else { return }
        fractions[index] = clamped
        recompute()
    }

    /// Marks one pick finished, whatever its outcome.
    func finish(at index: Int) {
        observations[index]?.invalidate()
        observations[index] = nil
        live[index] = nil
        fractions[index] = 1
        guard isRunning else { return }
        completed = min(completed + 1, total)
        recompute()
    }

    // MARK: - Cancellation

    /// Cancels every download in flight. Their loads then fail as `.cancelled`.
    func cancel() {
        guard isRunning, !isCancelled else { return }
        isCancelled = true
        live.values.forEach { $0.cancel() }
        stopObserving()
        onChange?()
    }

    // MARK: - Private

    private func stopObserving() {
        observations.values.forEach { $0.invalidate() }
        observations = [:]
        live = [:]
    }

    private func recompute() {
        guard total > 0 else {
            fraction = 0
            onChange?()
            return
        }
        let sum = fractions.values.reduce(0, +)
        fraction = min(sum / Double(total), 1)
        onChange?()
    }
}
