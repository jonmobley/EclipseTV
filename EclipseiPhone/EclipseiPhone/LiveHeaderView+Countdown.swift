//
//  LiveHeaderView+Countdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Countdown Hero Clock

extension LiveHeaderView {

    /// How long the hero will hold the outgoing preview waiting on a background.
    ///
    /// Matches the commit watchdog on output, so a file that never decodes costs
    /// the same worst case on both surfaces.
    static let countdownBackgroundHoldLimit: TimeInterval = 1.0

    /// Large remaining-time clock for a live Countdown, matching AirPlay layout.
    ///
    /// Uses a stable content key so ticks do not crossfade the hero.
    /// - Parameter isExpired: When true, the digits turn red (matches AirPlay).
    func configureCountdownClock(text: String, isExpired: Bool) {
        guard canCommitCountdownChrome() else { return }
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
            // Reset here, not at the call site: while the hero is holding for a
            // background it still belongs to the outgoing content, whose transport
            // must not be zeroed under it.
            self.updatePlayback(PlaybackState())

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
        countdownBackground?.onReady = nil
        countdownBackground?.stop()
        countdownBackground?.removeFromSuperview()
        countdownBackground = nil
        countdownBackgroundDeadline = nil
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
        guard let media = liveCountdownBackgroundMedia else {
            clearCountdownBackground()
            return
        }
        let view = countdownBackground ?? installCountdownBackground()
        view.apply(media)
        insertSubview(view, at: 0)
        bringSubviewToFront(countdownClockLabel)
        bringSubviewToFront(liveBadge)
        // On screen now, so nothing is being held for.
        view.alpha = 1
        countdownBackgroundDeadline = nil
        view.play()
    }

    /// Renderable background for the countdown currently live, if any.
    var liveCountdownBackgroundMedia: CountdownBackgroundMedia? {
        let background = CountdownController.shared.liveCountdownId
            .map { CountdownBackground.resolved(for: $0) } ?? .black
        return background.media
    }

    /// Whether the hero may show the countdown clock yet.
    ///
    /// No media means there is nothing to compose, so the clock shows at once.
    /// Otherwise the hero waits for the picture, and `isOverdue` is the escape hatch
    /// that stops an undecodable file from parking the hero on stale content.
    static func canCommitCountdownChrome(
        hasMedia: Bool,
        isBackgroundReady: Bool,
        isOverdue: Bool
    ) -> Bool {
        guard hasMedia else { return true }
        return isBackgroundReady || isOverdue
    }

    // MARK: - Private

    /// Starts or continues the hold, reporting whether chrome can commit now.
    ///
    /// Output holds the outgoing frame under its transition overlay until the
    /// composed countdown frame exists. The hero holds the outgoing preview the
    /// same way rather than showing a bare clock and popping the picture in behind
    /// it a beat later, so the phone matches the TV.
    private func canCommitCountdownChrome() -> Bool {
        guard let media = liveCountdownBackgroundMedia else { return true }
        let view = holdCountdownBackground(for: media)
        return Self.canCommitCountdownChrome(
            hasMedia: true,
            isBackgroundReady: view.isReadyForDisplay,
            isOverdue: isCountdownBackgroundOverdue
        )
    }

    /// Installs and starts decoding `media`, or returns the hold already running.
    ///
    /// Idempotent because ticks keep calling this while the clock is hidden: a
    /// background already carrying this media is never rebuilt or re-decoded.
    private func holdCountdownBackground(
        for media: CountdownBackgroundMedia
    ) -> CountdownBackgroundView {
        if let view = countdownBackground, view.media == media { return view }

        let view = countdownBackground ?? installCountdownBackground()
        // Transparent rather than hidden: a hidden AVPlayerLayer may never report a
        // frame, and this path should not have to fall back on the watchdog.
        view.alpha = 0
        countdownBackgroundDeadline = Date()
            .addingTimeInterval(Self.countdownBackgroundHoldLimit)
        view.onReady = { [weak self] in
            self?.commitCountdownChromeAfterHold()
        }
        view.apply(media)
        view.play()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.countdownBackgroundHoldLimit
        ) { [weak self] in
            self?.commitCountdownChromeAfterHold()
        }
        return view
    }

    /// Re-runs the chrome pass once the background reports in, or the hold expires.
    private func commitCountdownChromeAfterHold() {
        guard countdownBackground != nil,
              CountdownController.shared.liveCountdownId != nil else { return }
        let clock = CountdownController.shared
        configureCountdownClock(
            text: clock.displayString, isExpired: clock.remaining == 0
        )
    }

    private var isCountdownBackgroundOverdue: Bool {
        guard let deadline = countdownBackgroundDeadline else { return true }
        return Date() >= deadline
    }

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
