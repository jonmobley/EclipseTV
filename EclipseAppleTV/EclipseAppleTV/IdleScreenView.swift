//
//  IdleScreenView.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Full-screen calm idle picture: the Eclipse loop, muted, with a fading hint.
///
/// Plays the same Eclipse Screensaver loop the iPhone's Screensaver uses (shipped
/// in the TV app as its bundled loop), blended at the loop point when the blend is
/// ready. The view takes focus while shown so remote presses land here instead of
/// on the library tiles underneath; it reports them through `onPress`.
///
/// Thread Safety: Main thread only (UIKit / AVFoundation player).
final class IdleScreenView: UIView {

    // MARK: - Properties

    /// Called for every remote press while the idle screen has focus.
    var onPress: ((IdleScreenRules.Press) -> Void)?

    /// Called when Select is held (opens Options).
    var onLongSelect: (() -> Void)?

    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var hideHintWork: DispatchWorkItem?
    /// Set when a held Select opened Options, so its release isn't also a press.
    private var longSelectFired = false

    private let hintContainer: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        view.layer.cornerRadius = Layout.hintCornerRadius
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        return view
    }()

    private let hintLabel = IdleScreenView.makeLabel(
        text: IdleScreenRules.hintText, size: Layout.hintFontSize, weight: .medium, alpha: 0.95
    )

    private let browseLabel = IdleScreenView.makeLabel(
        text: IdleScreenRules.browseHintText, size: Layout.browseFontSize, weight: .regular, alpha: 0.7
    )

    private enum Layout {
        static let hintCornerRadius: CGFloat = 24
        static let hintFontSize: CGFloat = 32
        static let browseFontSize: CGFloat = 24
        static let hintBottomInset: CGFloat = 90
        static let hintPaddingH: CGFloat = 40
        static let hintPaddingV: CGFloat = 22
        static let lineSpacing: CGFloat = 8
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        accessibilityIdentifier = "idleScreen"
        isAccessibilityElement = true
        accessibilityLabel = IdleScreenRules.hintText
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        buildHint()
        addLongSelectRecognizer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Public Interface

    override var canBecomeFocused: Bool { true }

    /// Starts the loop (muted) and shows the hint.
    func start() {
        startLoopIfNeeded()
        showHint()
    }

    /// Stops the loop and releases the player.
    func stop() {
        hideHintWork?.cancel()
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
        hintContainer.alpha = 0
    }

    /// Fades the hint in, then out again after `IdleScreenRules.hintVisibleSeconds`.
    func showHint() {
        hideHintWork?.cancel()
        UIView.animate(withDuration: IdleScreenRules.hintFadeSeconds) {
            self.hintContainer.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: IdleScreenRules.hintFadeSeconds) {
                self?.hintContainer.alpha = 0
            }
        }
        hideHintWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IdleScreenRules.hintVisibleSeconds, execute: work)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    // MARK: - Remote Presses

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first else { return super.pressesBegan(presses, with: event) }
        let kind = Self.kind(of: press.type)
        if kind == .menu || kind == .select {
            // Menu goes up the chain (app exit / back); Select waits for release
            // so a hold can open Options instead.
            super.pressesBegan(presses, with: event)
            return
        }
        onPress?(kind)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first, press.type == .select else {
            return super.pressesEnded(presses, with: event)
        }
        if longSelectFired {
            longSelectFired = false
            return
        }
        onPress?(.select)
    }

    // MARK: - Private Helpers

    private static func kind(of type: UIPress.PressType) -> IdleScreenRules.Press {
        switch type {
        case .select: return .select
        case .playPause: return .playPause
        case .menu: return .menu
        case .upArrow, .downArrow, .leftArrow, .rightArrow: return .arrow
        default: return .other
        }
    }

    private func addLongSelectRecognizer() {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        hold.minimumPressDuration = IdleScreenRules.optionsHoldSeconds
        hold.cancelsTouchesInView = false
        addGestureRecognizer(hold)
    }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        longSelectFired = true
        onLongSelect?()
    }

    private func startLoopIfNeeded() {
        guard player == nil, let url = Self.loopURL else { return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        // Let tvOS still dim and start its own screensaver after a long idle.
        queue.preventsDisplaySleepDuringVideoPlayback = false
        let item = CrossfadeLoopComposer.cachedItem(for: url) ?? AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer.player = queue
        queue.play()
    }

    /// The Eclipse loop shipped with the app.
    private static var loopURL: URL? {
        ShippedVideo.bundledURLs.first
    }

    private func buildHint() {
        let stack = UIStackView(arrangedSubviews: [hintLabel, browseLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Layout.lineSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        hintContainer.contentView.addSubview(stack)
        addSubview(hintContainer)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: hintContainer.contentView.topAnchor, constant: Layout.hintPaddingV),
            stack.bottomAnchor.constraint(equalTo: hintContainer.contentView.bottomAnchor, constant: -Layout.hintPaddingV),
            stack.leadingAnchor.constraint(equalTo: hintContainer.contentView.leadingAnchor, constant: Layout.hintPaddingH),
            stack.trailingAnchor.constraint(equalTo: hintContainer.contentView.trailingAnchor, constant: -Layout.hintPaddingH),
            hintContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.hintBottomInset)
        ])
    }

    private static func makeLabel(text: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = UIColor.white.withAlphaComponent(alpha)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }
}
