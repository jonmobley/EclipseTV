//
//  PlaybackControlsView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PlaybackControlsView.swift
import UIKit

/// Remote transport controls overlaid on the live hero: skip back 10s, play/pause,
/// skip forward 10s, plus a scrubber with current-time / duration labels. Commands are
/// reported through closures; the host forwards them to the Apple TV. Incoming playback
/// status is applied via `update(isPlaying:currentTime:duration:)`.
final class PlaybackControlsView: UIView {

    // MARK: - Callbacks

    var onTogglePlayPause: (() -> Void)?
    /// Relative skip in seconds (negative = backward).
    var onSkip: ((Double) -> Void)?
    /// Absolute seek target in seconds (fired when the user finishes scrubbing).
    var onSeek: ((Double) -> Void)?

    // MARK: - Subviews

    private let skipBackButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let skipForwardButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let slider = UISlider()

    // MARK: - State

    /// True while the user is dragging the scrubber, so incoming status updates don't
    /// fight the thumb position.
    private var isScrubbing = false
    private var duration: Double = 0
    private var isPlaying = false

    /// Status updates from the TV only arrive a couple of times per second (and may be
    /// dropped), so we advance the scrubber locally between them. `anchorPosition` is the
    /// last position the TV reported; `anchorTimestamp` is the host clock time it landed.
    private var anchorPosition: Double = 0
    private var anchorTimestamp: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    private let skipInterval: Double = 10

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopDisplayLink()
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        layer.cornerRadius = 12
        layer.masksToBounds = true

        let buttonConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        configureControlButton(skipBackButton, systemName: "gobackward.10", config: buttonConfig)
        configureControlButton(skipForwardButton, systemName: "goforward.10", config: buttonConfig)

        let playConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        configureControlButton(playPauseButton, systemName: "play.fill", config: playConfig)

        skipBackButton.addTarget(self, action: #selector(skipBackTapped), for: .touchUpInside)
        skipForwardButton.addTarget(self, action: #selector(skipForwardTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [skipBackButton, playPauseButton, skipForwardButton])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.distribution = .equalCentering
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonStack)

        configureTimeLabel(currentTimeLabel)
        configureTimeLabel(durationLabel)
        currentTimeLabel.text = "0:00"
        durationLabel.text = "0:00"

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.4)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let scrubberStack = UIStackView(arrangedSubviews: [currentTimeLabel, slider, durationLabel])
        scrubberStack.axis = .horizontal
        scrubberStack.alignment = .center
        scrubberStack.spacing = 8
        scrubberStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrubberStack)

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),

            scrubberStack.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 8),
            scrubberStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrubberStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrubberStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    private func configureControlButton(_ button: UIButton, systemName: String, config: UIImage.SymbolConfiguration) {
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .white
    }

    private func configureTimeLabel(_ label: UILabel) {
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    // MARK: - Actions

    @objc private func playPauseTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTogglePlayPause?()
    }

    @objc private func skipBackTapped() {
        onSkip?(-skipInterval)
    }

    @objc private func skipForwardTapped() {
        onSkip?(skipInterval)
    }

    @objc private func sliderTouchDown() {
        isScrubbing = true
        stopDisplayLink()
    }

    @objc private func sliderValueChanged() {
        currentTimeLabel.text = Self.formatTime(Double(slider.value))
    }

    @objc private func sliderTouchUp() {
        isScrubbing = false
        let target = Double(slider.value)
        anchorPosition = target
        anchorTimestamp = CACurrentMediaTime()
        onSeek?(target)
        updateInterpolation()
    }

    // MARK: - State Updates

    /// Applies playback state pushed from the Apple TV and re-anchors local interpolation.
    func update(isPlaying: Bool, currentTime: Double, duration: Double) {
        self.duration = duration
        self.isPlaying = isPlaying
        setPlayPauseSymbol(isPlaying: isPlaying)

        slider.isEnabled = duration > 0
        durationLabel.text = Self.formatTime(duration)

        anchorPosition = min(currentTime, max(duration, 0))
        anchorTimestamp = CACurrentMediaTime()

        // Don't override the thumb while the user is actively scrubbing.
        if !isScrubbing {
            applyPosition(anchorPosition)
        }
        updateInterpolation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateInterpolation()
    }

    // MARK: - Local Interpolation

    /// Starts/stops the display link that advances the thumb between TV status updates.
    private func updateInterpolation() {
        let shouldRun = isPlaying && duration > 0 && !isScrubbing && window != nil
        shouldRun ? startDisplayLink() : stopDisplayLink()
    }

    fileprivate func interpolateTick() {
        guard isPlaying, !isScrubbing, duration > 0 else { return }
        let elapsed = CACurrentMediaTime() - anchorTimestamp
        let time = min(anchorPosition + elapsed, duration)
        applyPosition(time)
        if time >= duration { stopDisplayLink() }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(target: self),
                                 selector: #selector(DisplayLinkProxy.tick))
        link.preferredFramesPerSecond = 12
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func applyPosition(_ time: Double) {
        slider.maximumValue = Float(max(duration, 0.1))
        slider.setValue(Float(min(time, max(duration, 0))), animated: false)
        currentTimeLabel.text = Self.formatTime(time)
    }

    private func setPlayPauseSymbol(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        let playConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        playPauseButton.setImage(UIImage(systemName: symbol, withConfiguration: playConfig), for: .normal)
    }

    // MARK: - Helpers

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Forwards `CADisplayLink` callbacks without the link retaining the controls view,
/// which would otherwise create a retain cycle that keeps the link alive.
private final class DisplayLinkProxy: NSObject {
    private weak var target: PlaybackControlsView?

    init(target: PlaybackControlsView) {
        self.target = target
    }

    @objc func tick() {
        target?.interpolateTick()
    }
}
