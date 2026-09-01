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
            countdownClockHost.addSubview(countdownTimeLabel)
            NSLayoutConstraint.activate([
                countdownTimeLabel.centerXAnchor.constraint(
                    equalTo: countdownClockHost.centerXAnchor
                ),
                countdownTimeLabel.centerYAnchor.constraint(
                    equalTo: countdownClockHost.centerYAnchor
                ),
                countdownTimeLabel.leadingAnchor.constraint(
                    greaterThanOrEqualTo: countdownClockHost.leadingAnchor,
                    constant: 40
                ),
                countdownTimeLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: countdownClockHost.trailingAnchor,
                    constant: -40
                )
            ])
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
    }

    private func refreshCountdownClock() {
        let clock = CountdownController.shared
        countdownTimeLabel.text = clock.displayString
        countdownTimeLabel.textColor = clock.remaining == 0
            ? .systemRed
            : .white
        let side = max(countdownClockHost.bounds.width, 1)
        let size = max(48, min(side * 0.28, 280))
        countdownTimeLabel.font = .monospacedDigitSystemFont(
            ofSize: size,
            weight: .semibold
        )
    }
}
