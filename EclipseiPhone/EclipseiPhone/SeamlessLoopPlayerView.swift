//
//  SeamlessLoopPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Muted dual-player host that crossfades at the loop point for a seamless Screensaver.
final class SeamlessLoopPlayerView: UIView {

    /// Fired once the active player has a frame ready to display.
    var onReady: (() -> Void)?

    private let players: [AVPlayer]
    private let playerLayers: [AVPlayerLayer]
    private var activeIndex = 0
    private var timeObserver: Any?
    private var endObservers: [NSObjectProtocol] = []
    private var displayReadyObservation: NSKeyValueObservation?
    private var isCrossfading = false
    private var didSignalReady = false
    /// Fade-in only (underlay stays opaque) — simultaneous fades dip to black.
    private let fadeDuration: TimeInterval = 1.4

    /// Creates a looping player for the local (or remote) video at `url`.
    init(url: URL) {
        let primary = AVPlayer(url: url)
        let secondary = AVPlayer(url: url)
        players = [primary, secondary]
        let layerA = AVPlayerLayer(player: primary)
        let layerB = AVPlayerLayer(player: secondary)
        playerLayers = [layerA, layerB]
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
            player.actionAtItemEnd = .pause
            AirPlayVideoTransport.configureLayerOnlyPlayback(on: player)
        }
        observeReady()
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
        guard timeObserver == nil else {
            players[activeIndex].play()
            return
        }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = players[activeIndex].addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.considerCrossfade(at: time)
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
        for player in players {
            player.pause()
        }
        isCrossfading = false
    }

    // MARK: - Private

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
                guard let self, let player, !self.isCrossfading else { return }
                player.seek(to: .zero)
                player.play()
            }
            endObservers.append(observer)
        }
    }

    private func considerCrossfade(at time: CMTime) {
        guard !isCrossfading,
              let item = players[activeIndex].currentItem else { return }
        let duration = item.duration
        guard duration.isNumeric, duration.seconds.isFinite else { return }
        let remaining = duration.seconds - time.seconds
        guard remaining <= fadeDuration, remaining >= 0 else { return }
        beginCrossfade()
    }

    private func beginCrossfade() {
        isCrossfading = true
        let from = activeIndex
        let to = 1 - activeIndex
        let incoming = players[to]
        let fromLayer = playerLayers[from]
        let toLayer = playerLayers[to]

        incoming.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                guard finished else {
                    self.isCrossfading = false
                    return
                }
                // Preroll so the first frame exists before we reveal the layer.
                incoming.preroll(atRate: 1) { [weak self] prerolled in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard prerolled else {
                            self.isCrossfading = false
                            incoming.play()
                            return
                        }
                        self.layer.insertSublayer(toLayer, above: fromLayer)
                        fromLayer.opacity = 1
                        toLayer.opacity = 0
                        incoming.play()

                        CATransaction.begin()
                        CATransaction.setAnimationDuration(self.fadeDuration)
                        CATransaction.setCompletionBlock {
                            DispatchQueue.main.async { [weak self] in
                                self?.finishCrossfade(from: from, to: to)
                            }
                        }
                        // Fade only the incoming layer in — underlay stays fully opaque
                        // so black never shows through mid-blend.
                        toLayer.opacity = 1
                        CATransaction.commit()
                    }
                }
            }
        }
    }

    private func finishCrossfade(from: Int, to: Int) {
        playerLayers[from].opacity = 0
        players[from].pause()
        players[from].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        if let timeObserver {
            players[from].removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        activeIndex = to
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = players[to].addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.considerCrossfade(at: time)
        }
        isCrossfading = false
    }
}
