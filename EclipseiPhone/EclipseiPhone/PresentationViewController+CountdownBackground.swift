//
//  PresentationViewController+CountdownBackground.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Countdown Background

extension PresentationViewController {

    /// Background chosen for the countdown currently on output.
    var liveCountdownBackground: CountdownBackground {
        CountdownController.shared.liveCountdownId
            .map { CountdownBackground.resolved(for: $0) } ?? .black
    }

    /// Installs, updates, or removes the background behind the countdown clock.
    ///
    /// Lives inside `countdownClockHost` rather than `mediaContainer`: the host is
    /// already sized and rotated to the output canvas, so the background inherits
    /// Vertical-mount rotation and clipping without touching the media transition
    /// paths that countdown deliberately hides.
    func refreshCountdownBackground() {
        guard let media = liveCountdownBackground.media else {
            teardownCountdownBackground()
            return
        }
        let view = countdownBackgroundView ?? installCountdownBackgroundView()
        view.apply(media)
        layoutCountdownBackground()
        view.play()
    }

    /// Frames the background to the rotated clock host.
    func layoutCountdownBackground() {
        countdownBackgroundView?.frame = countdownClockHost.bounds
    }

    /// Stops and removes the background so a hidden clock never decodes video.
    func teardownCountdownBackground() {
        countdownBackgroundView?.stop()
        countdownBackgroundView?.removeFromSuperview()
        countdownBackgroundView = nil
    }

    // MARK: - Private

    private func installCountdownBackgroundView() -> CountdownBackgroundView {
        let view = CountdownBackgroundView()
        view.translatesAutoresizingMaskIntoConstraints = true
        countdownClockHost.insertSubview(view, at: 0)
        countdownClockHost.bringSubviewToFront(countdownTimeLabel)
        countdownBackgroundView = view
        return view
    }
}
