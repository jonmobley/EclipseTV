//
//  AudioMiniPlayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Floating card chrome for ambient music on the home screen.
///
/// The card grows out of the Music circle: same height, no gap, leading end
/// rounded to match. Stop and the mic duck live here; the circle only shows
/// or hides the card.
final class AudioMiniPlayerView: UIView, UIGestureRecognizerDelegate {

    /// Preferred height when visible. Matches `AudioMiniPlayerBubbleView.side`.
    static let preferredHeight: CGFloat = 64
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
    /// The card's trailing edge lands on the circle's vertical center.
    static var connectedOverlap: CGFloat { preferredHeight / 2 }
    /// Padding around the round mic and stop controls inside the bar.
    static let controlChromeInset: CGFloat = 4
    /// Round mic and stop controls; same size, filling the bar height.
    static let controlSide: CGFloat = preferredHeight - controlChromeInset * 2
    /// Gap between the mic and stop circles.
    static let controlGap: CGFloat = 6
    /// Trailing inset for stop: clears the circle bite, then the usual padding.
    static var controlTrailingInset: CGFloat { connectedOverlap + controlChromeInset }

    /// Round filled chrome shared by the mic and stop buttons.
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
        config.background.cornerRadius = controlSide / 2
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
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
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

    private let stopButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Stop"
        return button
    }()

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
        guard let track = player.currentTrack else {
            isHidden = true
            return
        }
        isHidden = false
        titleLabel.text = track.title
        if let playlist = player.playlistName, !playlist.isEmpty {
            let artist = track.subtitle
            subtitleLabel.text = artist.isEmpty ? playlist : "\(artist) · \(playlist)"
        } else {
            subtitleLabel.text = track.subtitle.isEmpty ? "Music" : track.subtitle
        }
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

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        configureStopButton()
        addSubview(fillView)
        addSubview(textStack)
        addSubview(duckButton)
        addSubview(stopButton)
        pinChrome(textStack: textStack)
        applyFloatingChrome()

        accessibilityLabel = "Now Playing"
        accessibilityHint = "Double tap to open Now Playing"

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        duckButton.addTarget(self, action: #selector(duckTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
    }

    private func pinChrome(textStack: UIStackView) {
        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: duckButton.leadingAnchor, constant: -8
            ),

            stopButton.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Self.controlTrailingInset
            ),
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: Self.controlSide),
            stopButton.heightAnchor.constraint(equalToConstant: Self.controlSide),

            duckButton.trailingAnchor.constraint(
                equalTo: stopButton.leadingAnchor, constant: -Self.controlGap
            ),
            duckButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            duckButton.widthAnchor.constraint(equalToConstant: Self.controlSide),
            duckButton.heightAnchor.constraint(equalToConstant: Self.controlSide)
        ])
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
            biteOnRight: effectiveUserInterfaceLayoutDirection != .rightToLeft
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

    @objc private func stopTapped() {
        Haptics.impactMedium()
        onStop?()
    }
}
