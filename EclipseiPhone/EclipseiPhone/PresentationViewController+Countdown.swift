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
        countdownClockHost.transform = .identity
        countdownClockHost.bounds = .zero
    }

    /// Fills the AirPlay surface with the mode-aspect clock (rotates when Vertical).
    func applyCountdownLayout() {
        guard !countdownContainer.isHidden else { return }
        applyRotatedLayout(to: countdownClockHost, in: countdownContainer, scale: 1)
        countdownClockHost.layoutIfNeeded()
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
            let refresh: (Notification) -> Void = { [weak self] _ in
                self?.refreshCountdownClock()
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
        let clock = CountdownController.shared
        let layout = clock.liveCountdownId.map {
            CountdownClockLayoutPreview.resolved(for: $0)
        } ?? .default
        layout.apply(
            to: countdownTimeLabel,
            text: clock.displayString,
            isExpired: clock.remaining == 0,
            in: countdownClockHost.bounds
        )
    }
}
