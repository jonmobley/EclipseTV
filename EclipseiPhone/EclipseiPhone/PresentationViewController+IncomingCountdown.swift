//
//  PresentationViewController+IncomingCountdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Incoming Countdown

extension PresentationViewController {

    /// Builds the countdown clock and its background in the transition overlay.
    ///
    /// The overlay used to be left plain black, which revealed a bare clock and let
    /// the background pop in once it decoded. Composing the real frame here — and
    /// waiting for the background before signalling ready — means the reveal shows
    /// the finished picture and the promotion to primary changes nothing on screen.
    func installIncomingCountdown(generation: Int) {
        let host = makeIncomingMediaHost()
        makeIncomingCountdownLabel(in: host)
        let media = liveCountdownBackground.media

        if let media {
            let background = CountdownBackgroundView()
            background.translatesAutoresizingMaskIntoConstraints = false
            host.insertSubview(background, at: 0)
            NSLayoutConstraint.activate([
                background.topAnchor.constraint(equalTo: host.topAnchor),
                background.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                background.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                background.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            ])
            incomingCountdownBackground = background
            background.onReady = { [weak self] in
                self?.notifyIfCurrent(generation)
            }
            background.apply(media)
            background.play()
        }

        layoutIncomingMediaHost()
        host.layoutIfNeeded()
        layoutIncomingCountdown()

        // Nothing to decode — the clock on black is already the finished frame.
        if media == nil {
            notifyIfCurrent(generation)
        }
    }

    /// Re-sizes the overlay clock after a rotation or Display Mode change.
    func layoutIncomingCountdown() {
        guard let label = incomingCountdownLabel,
              let host = incomingMediaHost else { return }
        applyLiveCountdownClock(to: label, in: host.bounds)
    }

    // MARK: - Private

    /// Mirrors `countdownTimeLabel` so the held frame and the primary match.
    private func makeIncomingCountdownLabel(in host: UIView) {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(label)
        incomingCountdownLabel = label
    }
}
