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
            self.refreshCountdownBackground()
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
        clearCountdownBackground()
    }

    /// Stops and removes the in-hero countdown background.
    func clearCountdownBackground() {
        countdownBackground?.stop()
        countdownBackground?.removeFromSuperview()
        countdownBackground = nil
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

    /// Mirrors the live countdown's background behind the hero clock.
    ///
    /// Callable while the clock is already up so choosing a background applies
    /// without rebuilding hero chrome. Not driven by ticks: resolving media touches
    /// the file system, and the digits change every second.
    func refreshCountdownBackground() {
        // The clock owns the hero or nothing does — never paint a background under
        // whatever other content happens to be live.
        guard !countdownClockLabel.isHidden else { return }
        let background = CountdownController.shared.liveCountdownId
            .map { CountdownBackground.resolved(for: $0) } ?? .black
        guard let media = background.media else {
            clearCountdownBackground()
            return
        }
        let view = countdownBackground ?? installCountdownBackground()
        view.apply(media)
        insertSubview(view, at: 0)
        bringSubviewToFront(countdownClockLabel)
        bringSubviewToFront(liveBadge)
        view.play()
    }

    // MARK: - Private

    private func installCountdownBackground() -> CountdownBackgroundView {
        let view = CountdownBackgroundView()
        view.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(view, at: 0)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        countdownBackground = view
        return view
    }

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
