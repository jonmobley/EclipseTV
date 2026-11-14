//
//  VideoTrimViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Full-screen trimmer: plays the video, and the yellow handles under it set where it
/// starts and ends. Save writes the shorter video over the library item (via the host).
final class VideoTrimViewController: UIViewController {

    /// Called with the trimmed file once it is written. The host stores it and dismisses.
    var onTrimmed: ((URL, VideoTrimRange) -> Void)?
    /// Called when the user cancels.
    var onCancel: (() -> Void)?

    private let sourceURL: URL
    private let player: AVPlayer
    private var range: VideoTrimRange
    private var timeObserver: Any?
    private var wasPlayingBeforeDrag = false
    private var isSaving = false

    private let playerView = TrimPlayerView()
    private let trimBar: VideoTrimBarView
    private let playButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var didLoadThumbnails = false
    private let buttonStack = UIStackView()
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []

    init(sourceURL: URL, duration: Double) {
        self.sourceURL = sourceURL
        self.player = AVPlayer(url: sourceURL)
        self.range = VideoTrimRange(duration: duration)
        self.trimBar = VideoTrimBarView(range: range)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        setupViews()
        setupPlayer()
        updateLabels()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didLoadThumbnails, trimBar.bounds.width > 0 {
            didLoadThumbnails = true
            loadThumbnails(count: trimBar.preferredThumbnailCount)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
    }

    // MARK: - Setup

    private func setupViews() {
        titleLabel.text = "Trim"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        playerView.playerLayer.player = player
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.isAccessibilityElement = true
        playerView.accessibilityLabel = "Video preview"

        let playConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        playButton.tintColor = .white
        playButton.accessibilityLabel = "Play"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timeLabel.textColor = .lightGray
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.8

        trimBar.onRangeChanged = { [weak self] range, edge in
            self?.rangeChanged(range, edge: edge)
        }
        trimBar.onScrub = { [weak self] seconds in
            self?.seek(to: seconds)
        }
        trimBar.onDragStateChanged = { [weak self] dragging in
            self?.dragStateChanged(dragging)
        }

        styleButton(cancelButton, title: "Cancel", titleColor: .systemRed,
                    background: UIColor.systemRed.withAlphaComponent(0.12))
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        styleButton(resetButton, title: "Reset", titleColor: .white,
                    background: UIColor.white.withAlphaComponent(0.15))
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        styleButton(saveButton, title: "Save", titleColor: .white, background: .accent)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addSubview(spinner)

        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(resetButton)
        buttonStack.addArrangedSubview(saveButton)
        buttonStack.distribution = .fillEqually

        let barRow = UIStackView(arrangedSubviews: [playButton, trimBar])
        barRow.axis = .horizontal
        barRow.spacing = 8
        barRow.alignment = .fill

        for sub in [titleLabel, playerView, timeLabel, barRow, buttonStack] as [UIView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            timeLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            barRow.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            barRow.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            spinner.centerXAnchor.constraint(equalTo: saveButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor)
        ])

        // Tall screens: title, video, times, film strip, then a row of buttons.
        portraitConstraints = [
            titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            playerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            playerView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -16),
            timeLabel.bottomAnchor.constraint(equalTo: barRow.topAnchor, constant: -12),
            barRow.heightAnchor.constraint(equalToConstant: 56),
            barRow.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -24),
            buttonStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
            buttonStack.heightAnchor.constraint(equalToConstant: 50)
        ]

        // Short (landscape) screens: no title, and the buttons stack beside the video so
        // the picture keeps most of the height.
        landscapeConstraints = [
            playerView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            playerView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            playerView.trailingAnchor.constraint(equalTo: buttonStack.leadingAnchor, constant: -16),
            playerView.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -10),
            timeLabel.bottomAnchor.constraint(equalTo: barRow.topAnchor, constant: -8),
            barRow.heightAnchor.constraint(equalToConstant: 48),
            barRow.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
            buttonStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            buttonStack.widthAnchor.constraint(equalToConstant: 150),
            buttonStack.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 152)
        ]

        applyLayoutForSizeClass()
        registerForTraitChanges([UITraitVerticalSizeClass.self]) { (self: Self, _) in
            self.applyLayoutForSizeClass()
        }
    }

    private func applyLayoutForSizeClass() {
        let isShort = traitCollection.verticalSizeClass == .compact
        NSLayoutConstraint.deactivate(isShort ? portraitConstraints : landscapeConstraints)
        titleLabel.isHidden = isShort
        buttonStack.axis = isShort ? .vertical : .horizontal
        buttonStack.spacing = isShort ? 10 : 12
        NSLayoutConstraint.activate(isShort ? landscapeConstraints : portraitConstraints)
    }

    private func styleButton(_ button: UIButton, title: String, titleColor: UIColor, background: UIColor) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(titleColor, for: .normal)
        button.backgroundColor = background
        button.layer.applyContinuousCorner(radius: CornerRadii.large)
    }

    private func setupPlayer() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.playerTimeChanged(time.seconds)
            }
        }
    }

    // MARK: - Playback

    private var isPlaying: Bool { player.timeControlStatus != .paused || player.rate != 0 }

    private func playerTimeChanged(_ seconds: Double) {
        guard seconds.isFinite else { return }
        // Loop inside the kept part, so the preview shows exactly what will be saved.
        if isPlaying, seconds >= range.end {
            seek(to: range.start)
            return
        }
        trimBar.playheadTime = seconds
    }

    private func seek(to seconds: Double) {
        trimBar.playheadTime = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func setPlaying(_ playing: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        if playing {
            let now = player.currentTime().seconds
            if !now.isFinite || now < range.start || now >= range.end - 0.05 {
                seek(to: range.start)
            }
            player.play()
        } else {
            player.pause()
        }
        playButton.setImage(
            UIImage(systemName: playing ? "pause.fill" : "play.fill", withConfiguration: config),
            for: .normal
        )
        playButton.accessibilityLabel = playing ? "Pause" : "Play"
    }

    // MARK: - Trim changes

    private func rangeChanged(_ newRange: VideoTrimRange, edge: VideoTrimBarView.Edge) {
        range = newRange
        // Show the frame under the handle being moved.
        seek(to: edge == .start ? range.start : range.end)
        updateLabels()
    }

    private func dragStateChanged(_ dragging: Bool) {
        if dragging {
            wasPlayingBeforeDrag = isPlaying
            if wasPlayingBeforeDrag { setPlaying(false) }
        } else if wasPlayingBeforeDrag {
            setPlaying(true)
        }
    }

    private func updateLabels() {
        timeLabel.text = "\(VideoTrimRange.label(range.start)) – \(VideoTrimRange.label(range.end))"
            + "   ·   \(VideoTrimRange.label(range.length))"
        timeLabel.accessibilityLabel = "Keeps \(VideoTrimRange.label(range.length)), from "
            + "\(VideoTrimRange.label(range.start)) to \(VideoTrimRange.label(range.end))"
        let trimmed = !range.isFullLength
        saveButton.isEnabled = trimmed && !isSaving
        saveButton.alpha = trimmed ? 1 : 0.45
        resetButton.isEnabled = trimmed && !isSaving
        resetButton.alpha = trimmed ? 1 : 0.45
    }

    // MARK: - Film strip

    private func loadThumbnails(count: Int) {
        let asset = AVURLAsset(url: sourceURL)
        let duration = range.duration
        let height = trimBar.bounds.height * (view.window?.screen.scale ?? 3)
        Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: height * 1.5, height: height)
            let tolerance = CMTime(seconds: max(duration / Double(count) / 2, 0.1), preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            var images: [UIImage] = []
            for index in 0..<count {
                let seconds = duration * (Double(index) + 0.5) / Double(count)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                if let cg = try? await generator.image(at: time).image {
                    images.append(UIImage(cgImage: cg))
                } else if let last = images.last {
                    images.append(last)
                }
            }
            await MainActor.run {
                self?.trimBar.setThumbnails(images)
            }
        }
    }

    // MARK: - Actions

    @objc private func playTapped() {
        setPlaying(!isPlaying)
    }

    @objc private func cancelTapped() {
        player.pause()
        onCancel?()
    }

    @objc private func resetTapped() {
        range.reset()
        trimBar.setRange(range)
        seek(to: 0)
        updateLabels()
    }

    @objc private func saveTapped() {
        guard !isSaving, !range.isFullLength else { return }
        isSaving = true
        setPlaying(false)
        saveButton.setTitle("", for: .normal)
        spinner.startAnimating()
        trimBar.isUserInteractionEnabled = false
        playButton.isEnabled = false
        updateLabels()
        let saved = range
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await VideoTrimExporter.export(
                    sourceURL: self.sourceURL, start: saved.start, end: saved.end
                )
                self.onTrimmed?(url, saved)
            } catch {
                self.saveFailed()
            }
        }
    }

    private func saveFailed() {
        isSaving = false
        spinner.stopAnimating()
        saveButton.setTitle("Save", for: .normal)
        trimBar.isUserInteractionEnabled = true
        playButton.isEnabled = true
        updateLabels()
        let alert = UIAlertController(
            title: "Couldn't trim this video",
            message: "Your video wasn't changed. Try again, or try a different video.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// A view whose backing layer is the video picture.
private final class TrimPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }
}
