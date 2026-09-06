//
//  PresentationViewController+Countdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Countdown Presentation

extension PresentationViewController {

    /// Shows the countdown clock on the external display.
    func showCountdown() {
        hideCamera()
        hideWeb()
        hidePDF()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()
        setIdleBrandVisible(false)

        installCountdownClockIfNeeded()
        countdownContainer.isHidden = false
        refreshCountdownClock()
        applyCountdownLayout()
    }

    /// Hides the countdown clock.
    func hideCountdown() {
        countdownContainer.isHidden = true
        // The host stays installed, so a background loop must be torn down here or
        // it keeps decoding video behind a collapsed, invisible view.
        teardownCountdownBackground()
        countdownClockHost.transform = .identity
        countdownClockHost.bounds = .zero
    }

    /// Fills the AirPlay surface with the mode-aspect clock (rotates when Vertical).
    func applyCountdownLayout() {
        guard !countdownContainer.isHidden else { return }
        applyRotatedLayout(to: countdownClockHost, in: countdownContainer, scale: 1)
        countdownClockHost.layoutIfNeeded()
        refreshCountdownBackground()
        refreshCountdownClock()
    }

    // MARK: - Private

    private func installCountdownClockIfNeeded() {
        if countdownClockHost.superview == nil {
            countdownClockHost.backgroundColor = .black
            countdownClockHost.translatesAutoresizingMaskIntoConstraints = true
            countdownContainer.addSubview(countdownClockHost)
            countdownTimeLabel.translatesAutoresizingMaskIntoConstraints = true
            countdownClockHost.addSubview(countdownTimeLabel)
        }
        if countdownObserver == nil {
            countdownObserver = NotificationCenter.default.addObserver(
                forName: CountdownController.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshCountdownClock()
            }
        }
        if countdownLayoutObserver == nil {
            // Store / draft changes can also change the background; ticks never do,
            // so the per-second observer above stays clock-only.
            let refresh: (Notification) -> Void = { [weak self] _ in
                guard let self else { return }
                self.refreshCountdownClock()
                guard !self.countdownContainer.isHidden else { return }
                self.refreshCountdownBackground()
            }
            countdownLayoutObserver = NotificationCenter.default.addObserver(
                forName: CountdownStore.didChangeNotification,
                object: nil,
                queue: .main,
                using: refresh
            )
            countdownPreviewObserver = NotificationCenter.default.addObserver(
                forName: CountdownClockLayoutPreview.didChangeNotification,
                object: nil,
                queue: .main,
                using: refresh
            )
        }
    }

    private func refreshCountdownClock() {
        applyLiveCountdownClock(to: countdownTimeLabel, in: countdownClockHost.bounds)
    }
}

// MARK: - Shared Clock Layout

extension PresentationViewController {

    /// Draws the live countdown's digits into `label`, sized for `bounds`.
    ///
    /// Shared with the transition overlay so the held frame matches the primary
    /// surface exactly and the promotion is invisible.
    func applyLiveCountdownClock(to label: UILabel, in bounds: CGRect) {
        let clock = CountdownController.shared
        let layout = clock.liveCountdownId.map {
            CountdownClockLayoutPreview.resolved(for: $0)
        } ?? .default
        layout.apply(
            to: label,
            text: clock.displayString,
            isExpired: clock.remaining == 0,
            in: bounds
        )
    }
}
