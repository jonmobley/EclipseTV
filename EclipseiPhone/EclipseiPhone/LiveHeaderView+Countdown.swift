//
//  LiveHeaderView+Countdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Countdown Hero Clock

extension LiveHeaderView {

    /// Large remaining-time clock for a live Countdown, matching AirPlay layout.
    ///
    /// Uses a stable content key so ticks do not crossfade the hero.
    /// - Parameter isExpired: When true, the digits turn red (matches AirPlay).
    func configureCountdownClock(text: String, isExpired: Bool) {
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        clearCameraPreview()
        clearLibraryVideoPreview()
        let showLiveBadge = LiveOutputRouting.showsHeroLiveBadge()
        applyContent(key: "overlay:countdown") {
            self.backgroundColor = UIColor(white: 0.08, alpha: 1)
            self.imageView.image = nil
            self.imageView.isHidden = true
            self.placeholderIcon.isHidden = true
            self.titleLabel.isHidden = true
            self.subtitleLabel.isHidden = true

            self.wantsPlaybackControls = false
            self.allowsFullscreenTap = false
            self.allowsHostControllerTap = false
            self.allowsCameraControllerTap = false
            self.gradientLayer.isHidden = true
            self.liveBadge.isHidden = !showLiveBadge
            self.controls.isHidden = true

            self.countdownClockLabel.isHidden = false
            self.layoutCountdownClock(text: text, isExpired: isExpired)
            self.bringSubviewToFront(self.countdownClockLabel)
            self.bringSubviewToFront(self.liveBadge)
            self.applyCollapseChrome()
            self.accessibilityLabel = self.isCompactPresentation
                ? "\(text), countdown, tap to expand"
                : "\(text), countdown"
        }
    }

    /// Updates clock digits during ticks without rebuilding hero chrome.
    func applyCountdownClock(text: String, isExpired: Bool) {
        countdownClockLabel.isHidden = false
        layoutCountdownClock(text: text, isExpired: isExpired)
    }

    /// Hides the countdown clock so it cannot leak onto other overlays.
    func hideCountdownClock() {
        countdownClockLabel.isHidden = true
        countdownClockLabel.text = nil
    }

    /// Positions the hero clock from the live countdown's saved or draft layout.
    func layoutCountdownClockIfNeeded() {
        guard !countdownClockLabel.isHidden else { return }
        let clock = CountdownController.shared
        layoutCountdownClock(
            text: countdownClockLabel.text ?? clock.displayString,
            isExpired: clock.remaining == 0
        )
    }

    // MARK: - Private

    private func layoutCountdownClock(text: String, isExpired: Bool) {
        let layout = CountdownController.shared.liveCountdownId.map {
            CountdownClockLayoutPreview.resolved(for: $0)
        } ?? .default
        layout.apply(
            to: countdownClockLabel,
            text: text,
            isExpired: isExpired,
            in: bounds
        )
    }
}
