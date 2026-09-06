//
//  SeamlessLoopPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Muted looping video host for the Screensaver.
///
/// With `crossfadesAtLoop` on, two players blend at the loop point so a clip that
/// doesn't loop cleanly never shows a cut. With it off, a single `AVPlayerLooper`
/// plays the clip gaplessly, which is what a perfectly looping clip wants.
final class SeamlessLoopPlayerView: UIView {

    /// Fired once the active player has a frame ready to display.
    var onReady: (() -> Void)?

    /// Whether the loop point is blended (dual player) or hard (gapless looper).
    let crossfadesAtLoop: Bool

    private let players: [AVPlayer]
    private let playerLayers: [AVPlayerLayer]
    private let looper: AVPlayerLooper?
    private var activeIndex = 0
    private var timeObserver: Any?
    private var endObservers: [NSObjectProtocol] = []
    private var displayReadyObservation: NSKeyValueObservation?
    private var standbyStatusObservation: NSKeyValueObservation?
    private var isCrossfading = false
    private var didSignalReady = false
    /// Fade-in only (underlay stays opaque) — simultaneous fades dip to black.
    private let fadeDuration: TimeInterval = 1.4

    /// Creates a looping player for the local (or remote) video at `url`.
    ///
    /// - Parameter crossfadesAtLoop: Blend the loop point. Off plays a hard, gapless loop.
    init(url: URL, crossfadesAtLoop: Bool = true) {
        self.crossfadesAtLoop = crossfadesAtLoop
        if crossfadesAtLoop {
            players = [AVPlayer(url: url), AVPlayer(url: url)]
            looper = nil
        } else {
            let queue = AVQueuePlayer()
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            players = [queue]
        }
        playerLayers = players.map { AVPlayerLayer(player: $0) }
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        for (index, layer) in playerLayers.enumerated() {
            layer.videoGravity = .resizeAspectFill
            layer.opacity = index == 0 ? 1 : 0
            self.layer.addSublayer(layer)
        }
        for player in players {
            player.isMuted = true
            AirPlayVideoTransport.configureLayerOnlyPlayback(on: player)
        }
        observeReady()
        guard crossfadesAtLoop else { return }
        for player in players {
            player.actionAtItemEnd = .pause
        }
        observeEnds()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for layer in playerLayers {
            layer.frame = bounds
        }
    }

    /// True once the active layer has a decoded frame (not just `readyToPlay`).
    var isReadyForDisplay: Bool {
        playerLayers[activeIndex].isReadyForDisplay
    }

    /// Starts muted playback from the current active player.
    func play() {
        if crossfadesAtLoop, timeObserver == nil {
            installLoopWatch(on: activeIndex)
            primeStandby()
        }
        players[activeIndex].play()
    }

    /// Pauses both players and removes observers.
    func stop() {
        if let timeObserver {
            players[activeIndex].removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        for observer in endObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        endObservers.removeAll()
        displayReadyObservation = nil
        standbyStatusObservation = nil
        for player in players {
            player.pause()
        }
        isCrossfading = false
    }

    // MARK: - Private

    /// Polls the active player so the blend can start `fadeDuration` before the end.
    private func installLoopWatch(on index: Int) {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = players[index].addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.considerCrossfade(at: time)
        }
    }

    private func observeReady() {
        let layer = playerLayers[0]
        displayReadyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay, !self.didSignalReady else { return }
            self.didSignalReady = true
            DispatchQueue.main.async { [weak self] in
                self?.onReady?()
            }
        }
    }

    private func observeEnds() {
        for player in players {
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self, weak player] _ in
                // Hard-loop fallback for the active player only (e.g. unknown duration).
                // The standby must stay paused and primed, or its preroll is voided.
                guard let self, let player, !self.isCrossfading,
                      player === self.players[self.activeIndex] else { return }
                player.seek(to: .zero)
                player.play()
            }
            endObservers.append(observer)
        }
    }

    /// Rewinds and prerolls the standby player so the blend can start the instant
    /// the active player nears its end. Waits for `readyToPlay` first: preroll throws
    /// before that, and fails whenever the player's rate is nonzero.
    private func primeStandby() {
        guard crossfadesAtLoop, players.count == 2 else { return }
        let standby = players[1 - activeIndex]
        standbyStatusObservation = nil
        guard standby.status == .readyToPlay else {
            standbyStatusObservation = standby.observe(\.status, options: [.new]) {
                [weak self] player, _ in
                guard player.status == .readyToPlay else { return }
                DispatchQueue.main.async { self?.primeStandby() }
            }
            return
        }
        guard standby.rate == 0 else { return }
        standby.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self, weak standby] finished in
            DispatchQueue.main.async {
                guard let self, let standby, finished, !self.isCrossfading,
                      standby === self.players[1 - self.activeIndex],
                      standby.rate == 0, standby.status == .readyToPlay else { return }
                standby.preroll(atRate: 1) { _ in }
            }
        }
    }

    private func considerCrossfade(at time: CMTime) {
        guard crossfadesAtLoop, !isCrossfading,
              let item = players[activeIndex].currentItem else { return }
        let duration = item.duration
        guard duration.isNumeric, duration.seconds.isFinite else { return }
        let remaining = duration.seconds - time.seconds
        guard remaining <= fadeDuration, remaining >= 0 else { return }
        beginCrossfade()
    }

    /// Starts the blend immediately. The standby was rewound and prerolled by
    /// `primeStandby()`, so nothing asynchronous sits between "1.4 s left" and the
    /// first blended frame — a late start would leave the outgoing clip frozen on
    /// its last frame for the tail of the fade.
    private func beginCrossfade() {
        isCrossfading = true
        standbyStatusObservation = nil
        let from = activeIndex
        let to = 1 - activeIndex
        let incoming = players[to]
        let fromLayer = playerLayers[from]
        let toLayer = playerLayers[to]

        if incoming.currentTime() != .zero {
            // Priming didn't land; rewind inline. AVPlayer orders the play after the seek,
            // and an undecoded AVPlayerLayer is transparent, so the underlay still shows.
            incoming.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.insertSublayer(toLayer, above: fromLayer)
        fromLayer.opacity = 1
        toLayer.opacity = 0
        CATransaction.commit()
        incoming.play()

        CATransaction.begin()
        CATransaction.setAnimationDuration(fadeDuration)
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.finishCrossfade(from: from, to: to) }
        }
        // Fade only the incoming layer in — underlay stays fully opaque so black
        // never shows through mid-blend.
        toLayer.opacity = 1
        CATransaction.commit()
    }

    private func finishCrossfade(from: Int, to: Int) {
        guard activeIndex == from else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayers[from].opacity = 0
        CATransaction.commit()
        players[from].pause()
        if let timeObserver {
            players[from].removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        activeIndex = to
        installLoopWatch(on: to)
        isCrossfading = false
        primeStandby()
    }
}
