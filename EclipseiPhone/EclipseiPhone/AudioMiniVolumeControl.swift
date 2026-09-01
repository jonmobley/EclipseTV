//
//  AudioMiniVolumeControl.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Speaker button that reveals a vertical volume slider above the footer.
final class AudioMiniVolumeControl: UIView {

    static let buttonSide: CGFloat = 44

    /// `notify` is false while dragging so lists don't reload every tick.
    var onVolumeChange: ((_ value: Float, _ notify: Bool) -> Void)?

    private(set) var isExpanded = false
    /// Percent badge above the slider; true while dragging and shortly after.
    private(set) var isReadoutVisible = false
    private var volume: Float = 1
    private var readoutHideWork: DispatchWorkItem?

    private let speakerButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        return button
    }()

    private let panel: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isHidden = true
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: 8)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let bar = AudioMiniVolumeBar()

    private let readout: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isHidden = true
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.transform = CGAffineTransform(translationX: 0, y: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let readoutLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Percent shown above the slider while the finger covers the fill.
    static func percentText(for volume: Float) -> String {
        "\(Int((min(1, max(0, volume)) * 100).rounded()))%"
    }

    /// Updates the closed icon and open bar without collapsing the panel.
    func setVolume(_ volume: Float) {
        self.volume = min(1, max(0, volume))
        bar.value = self.volume
        refreshSpeaker()
        refreshReadout()
    }

    /// Drives the bar as a press would; used by the slider and by tests.
    func applyDragVolume(_ value: Float) {
        setVolume(value)
        showReadout()
        onVolumeChange?(volume, false)
    }

    /// Commits the mix level and keeps the percent badge up briefly.
    func finishDragVolume() {
        onVolumeChange?(volume, true)
        hideReadoutAfterDelay()
    }

    /// Shows or hides the vertical slider above the speaker.
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if !expanded { hideReadout(animated: false) }
        refreshSpeaker()
        speakerButton.accessibilityHint = expanded
            ? "Hides the volume slider."
            : "Shows a volume slider above the player."
        let changes = {
            self.panel.alpha = expanded ? 1 : 0
            self.panel.transform = expanded
                ? .identity
                : CGAffineTransform(translationX: 0, y: 8)
        }
        panel.isHidden = false
        panel.isUserInteractionEnabled = expanded
        if !animated || UIAccessibility.isReduceMotionEnabled {
            changes()
            if !expanded { panel.isHidden = true }
            return
        }
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            changes()
        } completion: { [weak self] _ in
            guard let self, !self.isExpanded else { return }
            self.panel.isHidden = true
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        guard isExpanded, !panel.isHidden else { return false }
        return panel.frame.contains(point)
    }

    // MARK: - Private

    private func setup() {
        clipsToBounds = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onChanged = { [weak self] value in
            self?.applyDragVolume(value)
        }
        bar.onEnded = { [weak self] in
            self?.finishDragVolume()
        }
        configureSpeaker()
        readout.contentView.addSubview(readoutLabel)
        panel.contentView.addSubview(bar)
        addSubview(speakerButton)
        addSubview(panel)
        addSubview(readout)
        activateConstraints()
        refreshSpeaker()
        refreshReadout()
    }

    private func configureSpeaker() {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        speakerButton.configuration = config
        speakerButton.accessibilityLabel = "Volume"
        speakerButton.accessibilityHint = "Shows a volume slider above the player."
        speakerButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate(
            speakerConstraints() + panelConstraints() + readoutConstraints()
        )
    }

    private func speakerConstraints() -> [NSLayoutConstraint] {
        [
            speakerButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            speakerButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            speakerButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            speakerButton.topAnchor.constraint(equalTo: topAnchor),
            speakerButton.widthAnchor.constraint(equalToConstant: Self.buttonSide),
            speakerButton.heightAnchor.constraint(equalToConstant: Self.buttonSide)
        ]
    }

    private func panelConstraints() -> [NSLayoutConstraint] {
        [
            panel.centerXAnchor.constraint(equalTo: speakerButton.centerXAnchor),
            panel.bottomAnchor.constraint(equalTo: speakerButton.topAnchor, constant: -10),
            panel.widthAnchor.constraint(equalToConstant: 36),
            panel.heightAnchor.constraint(equalToConstant: 132),
            bar.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 6),
            bar.trailingAnchor.constraint(
                equalTo: panel.contentView.trailingAnchor, constant: -6
            ),
            bar.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -6)
        ]
    }

    private func readoutConstraints() -> [NSLayoutConstraint] {
        [
            readout.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            readout.bottomAnchor.constraint(equalTo: panel.topAnchor, constant: -8),
            readout.heightAnchor.constraint(equalToConstant: 28),
            readout.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            readoutLabel.topAnchor.constraint(
                equalTo: readout.contentView.topAnchor, constant: 4
            ),
            readoutLabel.bottomAnchor.constraint(
                equalTo: readout.contentView.bottomAnchor, constant: -4
            ),
            readoutLabel.leadingAnchor.constraint(
                equalTo: readout.contentView.leadingAnchor, constant: 10
            ),
            readoutLabel.trailingAnchor.constraint(
                equalTo: readout.contentView.trailingAnchor, constant: -10
            )
        ]
    }

    private func refreshReadout() {
        readoutLabel.text = Self.percentText(for: volume)
    }

    private func showReadout() {
        readoutHideWork?.cancel()
        readoutHideWork = nil
        setReadoutVisible(true, animated: true)
    }

    private func hideReadoutAfterDelay() {
        readoutHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideReadout(animated: true)
        }
        readoutHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private func hideReadout(animated: Bool) {
        readoutHideWork?.cancel()
        readoutHideWork = nil
        setReadoutVisible(false, animated: animated)
    }

    private func setReadoutVisible(_ visible: Bool, animated: Bool) {
        isReadoutVisible = visible
        refreshReadout()
        let changes = {
            self.readout.alpha = visible ? 1 : 0
            self.readout.transform = visible
                ? .identity
                : CGAffineTransform(translationX: 0, y: 6)
        }
        readout.isHidden = false
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled
        if !shouldAnimate {
            changes()
            if !visible { readout.isHidden = true }
            return
        }
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            changes()
        } completion: { [weak self] _ in
            guard let self, !self.isReadoutVisible else { return }
            self.readout.isHidden = true
        }
    }

    private func refreshSpeaker() {
        var config = speakerButton.configuration ?? .plain()
        config.image = UIImage(
            systemName: Self.speakerSymbol(for: volume),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        config.baseForegroundColor = .secondaryLabel
        speakerButton.configuration = config
        speakerButton.accessibilityValue = "\(Int((volume * 100).rounded())) percent"
    }

    private static func speakerSymbol(for volume: Float) -> String {
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.4 { return "speaker.wave.1.fill" }
        if volume < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @objc private func toggleExpanded() {
        setExpanded(!isExpanded, animated: true)
    }
}
