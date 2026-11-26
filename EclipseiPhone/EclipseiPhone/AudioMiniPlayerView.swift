//
//  AudioMiniPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Floating card chrome for ambient music on the home screen.
///
/// Two rows (2026-11-25): the song name on top, then mic duck, Pause, Stop
/// and Next. The Music circle sits in the card's bottom trailing corner, level
/// with the buttons; it only shows or hides the card.
final class AudioMiniPlayerView: UIView, UIGestureRecognizerDelegate {

    /// Height of the button row. Matches `AudioMiniPlayerBubbleView.side`.
    static let controlRowHeight: CGFloat = 64
    /// Height of the song-name row above the buttons.
    static let titleRowHeight: CGFloat = 44
    /// Preferred height when visible: the song name over the button row.
    static let preferredHeight: CGFloat = controlRowHeight + titleRowHeight
    /// Top corners; the bottom ones follow the round buttons (`controlRowHeight / 2`).
    static let topCornerRadius: CGFloat = 26
    /// Solid fill under the chrome.
    static let barBackgroundColor: UIColor = .secondarySystemBackground
    /// Visible card width, not counting the portion tucked under the circle.
    static let compactWidth: CGFloat = 360
    /// Narrowest the card squeezes to before it would clip its own controls.
    static let minimumCompactWidth: CGFloat = 200
    /// Sheet corner shared with Now Playing and the Music picker.
    static let compactCornerRadius: CGFloat = 20
    /// Matches the Music bubble so the bar grows from the same corner.
    static let compactTrailingInset: CGFloat = 16
    /// Gap from the screen bottom (not the safe area) so the circle sits in the corner.
    static let compactBottomInset: CGFloat = 10
    /// The card runs under the whole Music circle, which sits in its corner.
    static var connectedOverlap: CGFloat { controlRowHeight }
    /// Padding around the round mic and stop controls inside the bar.
    static let controlChromeInset: CGFloat = 4
    /// Round controls; same size, filling the button row.
    static let controlSide: CGFloat = controlRowHeight - controlChromeInset * 2
    /// Smallest gap between the round controls; spare width is shared between them.
    static let controlGap: CGFloat = 6

    /// Round filled chrome shared by the card's buttons.
    static func roundControlConfiguration(
        systemName: String,
        pointSize: CGFloat = 18,
        prominent: Bool = false
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: pointSize, weight: .bold
            )
        )
        config.baseForegroundColor = prominent ? .white : .secondaryLabel
        config.background.backgroundColor = prominent
            ? .accent
            : UIColor.white.withAlphaComponent(0.12)
        // Capsule, not a fixed radius: stays round if a narrow window squeezes the buttons.
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 16, leading: 16, bottom: 16, trailing: 16
        )
        return config
    }

    /// Card width for a host of `containerWidth`, leaving the Music circle on
    /// the trailing edge and the same inset on the leading edge.
    ///
    /// The frame includes `connectedOverlap`, which sits under the circle.
    /// The floor keeps the card usable on the narrowest phones and guards the
    /// zero-width container that Auto Layout reports during early layout.
    static func cardWidth(
        containerWidth: CGFloat,
        horizontalSafeArea: CGFloat
    ) -> CGFloat {
        let available = containerWidth - horizontalSafeArea
            - compactTrailingInset * 2
            - AudioMiniPlayerBubbleView.side
            + connectedOverlap
        let widest = compactWidth + connectedOverlap
        return max(minimumCompactWidth, min(widest, available))
    }

    var onOpenLibrary: (() -> Void)?
    /// Fades out and stops playback.
    var onStop: (() -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        // One line across the card's full width, above the buttons; artist and
        // playlist are still read out by VoiceOver.
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let fillView: UIView = {
        let view = UIView()
        view.backgroundColor = AudioMiniPlayerView.barBackgroundColor
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let fillMask = CAShapeLayer()

    private let duckButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Duck volume"
        return button
    }()

    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let stopButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Stop"
        return button
    }()

    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Next song"
        return button
    }()

    /// Hints that a tap on the song name opens Now Playing.
    private let openChevron: UIImageView = {
        let view = UIImageView(image: UIImage(
            systemName: "chevron.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ))
        view.tintColor = .tertiaryLabel
        view.isAccessibilityElement = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Mic duck, Pause, Stop, Next (owner's order, 2026-11-25).
    private lazy var controlStack: UIStackView = {
        // The empty last item gives Next the same gap to the Music circle as
        // the buttons have between each other.
        let circleGap = UIView()
        circleGap.isUserInteractionEnabled = false
        circleGap.widthAnchor.constraint(equalToConstant: 0).isActive = true
        let stack = UIStackView(
            arrangedSubviews: [duckButton, playPauseButton, stopButton, nextButton, circleGap]
        )
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .equalSpacing
        stack.spacing = Self.controlGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// The round controls, leading to trailing.
    var controlButtons: [UIButton] {
        controlStack.arrangedSubviews.compactMap { $0 as? UIButton }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Drop shadow matching the Music circle. The fill mask supplies the shape.
    func applyFloatingChrome() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    /// Refreshes labels and the mic duck from `AudioPlayerController`.
    func reload() {
        let player = AudioPlayerController.shared
        applyDuckChrome(ducked: player.isDucked)
        applyPlaybackChrome(playing: player.isPlaying, hasNextSong: player.hasNextSong)
        guard let track = player.currentTrack else {
            isHidden = true
            return
        }
        isHidden = false
        let details: String
        if let playlist = player.playlistName, !playlist.isEmpty {
            let artist = track.subtitle
            details = artist.isEmpty ? playlist : "\(artist) · \(playlist)"
        } else {
            details = track.subtitle
        }
        showTrack(title: track.title, details: details)
    }

    /// Song name on one line; artist and playlist only for VoiceOver.
    func showTrack(title: String, details: String) {
        titleLabel.text = title
        // The bar itself is not an accessibility element (its buttons are), so
        // the title label is what VoiceOver reads: song, then artist and playlist.
        titleLabel.accessibilityValue = details.isEmpty ? title : "\(title), \(details)"
    }

    /// What VoiceOver reads for the track (song, then artist and playlist).
    var spokenTrack: String? { titleLabel.accessibilityValue }

    /// Lines the song name currently needs (tests).
    var titleLineCount: Int {
        guard let font = titleLabel.font, titleLabel.bounds.width > 0 else { return 0 }
        let height = titleLabel.sizeThatFits(
            CGSize(width: titleLabel.bounds.width, height: .greatestFiniteMagnitude)
        ).height
        return Int((height / font.lineHeight).rounded())
    }

    /// Pause while playing, Play while paused. Next dims when there is no other
    /// song to move to (a single song with nothing in Up Next).
    func applyPlaybackChrome(playing: Bool, hasNextSong: Bool) {
        playPauseButton.configuration = Self.roundControlConfiguration(
            systemName: playing ? "pause.fill" : "play.fill"
        )
        playPauseButton.accessibilityLabel = playing ? "Pause" : "Play"
        playPauseButton.accessibilityHint = playing
            ? "Pauses the music. The player stays open."
            : "Resumes the music."
        nextButton.isEnabled = hasNextSong
    }

    /// Mic on (accent) while volume is ducked.
    func applyDuckChrome(ducked: Bool) {
        duckButton.configuration = Self.roundControlConfiguration(
            systemName: ducked ? "mic.fill" : "mic",
            prominent: ducked
        )
        duckButton.accessibilityValue = ducked ? "On" : "Off"
        duckButton.accessibilityHint = ducked
            ? "Restores the music volume."
            : "Lowers the music so you can talk over it."
    }

    // MARK: - Private

    private func setup() {
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        fillView.layer.mask = fillMask

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureStopButton()
        nextButton.configuration = Self.roundControlConfiguration(
            systemName: "forward.end.fill", pointSize: 16
        )
        nextButton.accessibilityHint = "Skips to the next song."
        applyPlaybackChrome(playing: false, hasNextSong: false)
        addSubview(fillView)
        addSubview(titleLabel)
        addSubview(openChevron)
        addSubview(controlStack)
        pinChrome()
        applyFloatingChrome()

        // VoiceOver focuses the title (a double tap lands on the bar's open tap).
        titleLabel.accessibilityLabel = "Now Playing"
        titleLabel.accessibilityHint = "Double tap to open Now Playing"
        titleLabel.accessibilityTraits = .button

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        duckButton.addTarget(self, action: #selector(duckTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
    }

    private func pinChrome() {
        // Song name sits in the top row, a touch below its middle so the gap to
        // the buttons matches the gap to the card's top edge.
        let titleRow = UILayoutGuide()
        addLayoutGuide(titleRow)
        var constraints = [
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleRow.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleRow.bottomAnchor.constraint(equalTo: controlStack.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                equalTo: openChevron.leadingAnchor, constant: -8
            ),
            openChevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            openChevron.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            controlStack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Self.controlChromeInset
            ),
            controlStack.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Self.connectedOverlap
            ),
            controlStack.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -Self.controlChromeInset
            ),
            controlStack.heightAnchor.constraint(equalToConstant: Self.controlSide)
        ]
        // Full-size circles when there is room; a very narrow window (iPad Slide
        // Over) shrinks all four evenly instead of clipping the last one.
        for button in controlButtons {
            let width = button.widthAnchor.constraint(equalToConstant: Self.controlSide)
            width.priority = UILayoutPriority(999)
            constraints.append(width)
            constraints.append(
                button.widthAnchor.constraint(lessThanOrEqualToConstant: Self.controlSide)
            )
            if button !== duckButton {
                constraints.append(
                    button.widthAnchor.constraint(equalTo: duckButton.widthAnchor)
                )
            }
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func configureStopButton() {
        stopButton.configuration = Self.roundControlConfiguration(
            systemName: "stop.fill", pointSize: 16
        )
        stopButton.accessibilityHint = "Fades out and stops playback."
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = AudioMiniPlayerShape.maskPath(
            in: bounds,
            topRadius: Self.topCornerRadius,
            bottomRadius: Self.controlRowHeight / 2
        )
        fillMask.frame = bounds
        fillMask.path = path.cgPath
        layer.shadowPath = path.cgPath
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let view = touch.view else { return true }
        return !(view is UIControl)
    }

    @objc private func openTapped() {
        onOpenLibrary?()
    }

    @objc private func duckTapped() {
        Haptics.selection()
        let player = AudioPlayerController.shared
        player.setDucked(!player.isDucked)
    }

    @objc private func playPauseTapped() {
        Haptics.selection()
        AudioPlayerController.shared.togglePlayPause()
    }

    @objc private func nextTapped() {
        Haptics.selection()
        AudioPlayerController.shared.playNext()
    }

    @objc private func stopTapped() {
        Haptics.impactMedium()
        onStop?()
    }
}
