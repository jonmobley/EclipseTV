//
//  CountdownBackgroundView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Aspect-fill still or muted loop behind a countdown clock, under a fixed scrim.
///
/// Shared by the external display, the phone hero, and the layout editor canvas so
/// all three frame the clock against the same picture.
final class CountdownBackgroundView: UIView {

    /// Media currently installed, if any.
    private(set) var media: CountdownBackgroundMedia?

    /// Fired once there is a frame to show — decoded still or first video frame.
    ///
    /// Lets the transition hold its opaque overlay until the background is painted,
    /// so the picture never pops in after the clock.
    var onReady: (() -> Void)?

    /// True once the installed media has been painted (or has nothing to wait for).
    ///
    /// Reports true for an undecodable file as well, so a bad image can't stall a
    /// caller waiting on readiness.
    var isReadyForDisplay: Bool { didSignalReady }

    /// True while a loop is installed and playing.
    var isLoopPlaying: Bool { isPlaying && loop != nil }

    private let imageView = UIImageView()
    private let scrim = UIView()
    private var loop: SeamlessLoopPlayerView?
    private var decodeGeneration = 0
    private var isPlaying = false
    private var didSignalReady = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Transparent until media is set so an empty background shows whatever the
        // host uses for "no background" (black on output, grey on the editor canvas).
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        scrim.backgroundColor = UIColor.black.withAlphaComponent(
            CountdownBackground.scrimAlpha
        )
        scrim.isHidden = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrim)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    /// Installs `media`, rebuilding only when it differs from what is showing.
    ///
    /// Countdown ticks re-run the whole chrome pass once a second, so an unguarded
    /// rebuild would restart the loop (and re-decode the still) on every tick.
    func apply(_ media: CountdownBackgroundMedia?) {
        guard media != self.media else { return }
        self.media = media
        teardownLoop()
        imageView.image = nil
        decodeGeneration += 1
        didSignalReady = false
        // A black plate covers the gap while a still decodes off the main thread.
        backgroundColor = media == nil ? .clear : .black

        switch media {
        case nil:
            scrim.isHidden = true
            signalReady()
        case .still(let url):
            scrim.isHidden = false
            loadStill(at: url, generation: decodeGeneration)
        case .loop(let url, let crossfade):
            scrim.isHidden = false
            installLoop(url: url, crossfade: crossfade)
        }
    }

    /// Starts the loop. No-op for a still or an empty background.
    func play() {
        isPlaying = true
        loop?.play()
    }

    /// Pauses the loop so a hidden background stops decoding video.
    ///
    /// Callers must invoke this before removing the view: the clock host is kept
    /// installed and merely collapsed when countdown leaves output, so a loop left
    /// running would decode forever behind nothing.
    func stop() {
        isPlaying = false
        loop?.stop()
    }

    // MARK: - Private

    private func signalReady() {
        guard !didSignalReady else { return }
        didSignalReady = true
        DispatchQueue.main.async { [weak self] in
            self?.onReady?()
        }
    }

    private func installLoop(url: URL, crossfade: Bool) {
        let view = SeamlessLoopPlayerView(url: url, crossfadesAtLoop: crossfade)
        view.onReady = { [weak self] in
            self?.signalReady()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(view, belowSubview: scrim)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        loop = view
        if isPlaying { view.play() }
    }

    private func teardownLoop() {
        loop?.stop()
        loop?.removeFromSuperview()
        loop = nil
    }

    /// Decodes off the main thread at panel size — a full-res still would hitch the
    /// AirPlay encode at the exact moment the clock appears.
    private func loadStill(at url: URL, generation: Int) {
        let maxEdge = PresentationImageDecoder.maxPixelEdge(for: window?.screen)
        DispatchQueue.global(qos: .userInitiated).async {
            let image = PresentationImageDecoder.decode(
                fileURL: url, maxPixelEdge: maxEdge
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.decodeGeneration == generation else { return }
                self.imageView.image = image
                self.signalReady()
            }
        }
    }
}
