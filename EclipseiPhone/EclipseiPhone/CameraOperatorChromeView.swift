//
//  CameraOperatorChromeView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - CameraOperatorChromeView

/// Camera Mode extras laid over the full-screen Camera.
///
/// - Status pill: whether the picture is reaching the Mac.
/// - Hold to Exit: replaces Back so a volunteer can't leave by accident.
/// - Connect card: shown until the Mac is connected, with Scan Mac QR Code.
///
/// Touches outside these controls fall through to the camera underneath, so
/// pinch-to-zoom, Flip, frames and stills keep working. Main thread only.
final class CameraOperatorChromeView: UIView {

    // MARK: - Constants

    /// How long Hold to Exit must be held.
    static let exitHoldDuration: TimeInterval = 1.0
    private static let pillHeight: CGFloat = 30
    private static let exitSize = CGSize(width: 160, height: 40)
    private static let cardWidth: CGFloat = 300

    // MARK: - Callbacks

    /// Invoked after a completed hold on Hold to Exit.
    var onExit: (() -> Void)?
    /// Invoked by Scan Mac QR Code.
    var onScan: (() -> Void)?

    // MARK: - Subviews

    private let statusPill = UILabel()
    private let exitButton = UIButton(type: .system)
    private let exitFill = UIView()
    private let card = UIView()
    private let cardLabel = UILabel()
    private let scanButton = UIButton(type: .system)

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStatusPill()
        setupExitButton()
        setupCard()
        apply(status: CameraOperatorMode.shared.macStatus)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Public Interface

    /// Updates the pill and card for a Mac link state.
    /// - Parameter status: Current Camera Mode Mac status.
    func apply(status: CameraOperatorMode.MacStatus) {
        let text = CameraOperatorChromeText.pill(for: status)
        statusPill.text = "  \(text.title)  "
        statusPill.backgroundColor = text.color
        statusPill.accessibilityLabel = text.title
        let message = CameraOperatorChromeText.cardMessage(for: status)
        card.isHidden = message == nil
        cardLabel.text = message
        setNeedsLayout()
    }

    /// Places the controls around the camera panel.
    /// - Parameters:
    ///   - panel: Camera panel frame in this view's coordinates.
    ///   - exitFrame: Where Back normally sits (Hold to Exit takes its place).
    func layout(panel: CGRect, exitFrame: CGRect) {
        frame = superview?.bounds ?? frame
        exitButton.frame = CGRect(
            origin: CGPoint(x: exitFrame.minX, y: exitFrame.midY - Self.exitSize.height / 2),
            size: Self.exitSize
        )
        exitFill.frame = CGRect(x: 0, y: 0, width: 0, height: Self.exitSize.height)
        let pillWidth = statusPill.intrinsicContentSize.width
        statusPill.frame = CGRect(
            x: panel.midX - pillWidth / 2,
            y: exitButton.frame.maxY + 10,
            width: pillWidth,
            height: Self.pillHeight
        )
        let width = min(Self.cardWidth, panel.width - 32)
        let labelHeight = cardLabel.sizeThatFits(CGSize(width: width - 32, height: .greatestFiniteMagnitude)).height
        let height = labelHeight + 16 + 44 + 32
        card.frame = CGRect(x: panel.midX - width / 2, y: panel.midY - height / 2, width: width, height: height)
        cardLabel.frame = CGRect(x: 16, y: 16, width: width - 32, height: labelHeight)
        scanButton.frame = CGRect(x: 16, y: cardLabel.frame.maxY + 16, width: width - 32, height: 44)
    }

    // MARK: - Touch Pass-Through

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        [exitButton, card].contains { control in
            !control.isHidden && control.frame.contains(point)
        }
    }

    // MARK: - Private Helpers

    private func setupStatusPill() {
        statusPill.font = .systemFont(ofSize: 14, weight: .semibold)
        statusPill.textColor = .white
        statusPill.layer.cornerRadius = Self.pillHeight / 2
        statusPill.layer.masksToBounds = true
        statusPill.isUserInteractionEnabled = false
        addSubview(statusPill)
    }

    private func setupExitButton() {
        var config = UIButton.Configuration.filled()
        config.title = "Hold to Exit"
        config.image = UIImage(systemName: "xmark")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        exitButton.configuration = config
        exitButton.clipsToBounds = true
        exitButton.accessibilityHint = "Press and hold to leave Camera Mode."
        exitFill.backgroundColor = UIColor.systemRed.withAlphaComponent(0.7)
        exitFill.isUserInteractionEnabled = false
        exitButton.insertSubview(exitFill, at: 0)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(exitHeld(_:)))
        hold.minimumPressDuration = Self.exitHoldDuration
        exitButton.addGestureRecognizer(hold)
        exitButton.addTarget(self, action: #selector(exitTouchDown), for: .touchDown)
        exitButton.addTarget(self, action: #selector(exitTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addSubview(exitButton)
    }

    private func setupCard() {
        card.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        card.layer.cornerRadius = 16
        cardLabel.font = .systemFont(ofSize: 15, weight: .medium)
        cardLabel.textColor = .white
        cardLabel.numberOfLines = 0
        cardLabel.textAlignment = .center
        var config = UIButton.Configuration.filled()
        config.title = "Scan Mac QR Code"
        config.image = UIImage(systemName: "qrcode.viewfinder")
        config.imagePadding = 8
        config.cornerStyle = .capsule
        scanButton.configuration = config
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        card.addSubview(cardLabel)
        card.addSubview(scanButton)
        addSubview(card)
    }

    /// Fills the button left to right over the hold time.
    @objc private func exitTouchDown() {
        exitFill.frame.size.width = 0
        UIView.animate(withDuration: Self.exitHoldDuration, delay: 0, options: [.curveLinear]) {
            self.exitFill.frame.size.width = self.exitButton.bounds.width
        }
    }

    @objc private func exitTouchEnded() {
        exitFill.layer.removeAllAnimations()
        exitFill.frame.size.width = 0
    }

    @objc private func exitHeld(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        Haptics.impactMedium()
        onExit?()
    }

    @objc private func scanTapped() {
        onScan?()
    }
}

// MARK: - CameraOperatorChromeText

/// Words and colours for Camera Mode's Mac status (pure, testable).
enum CameraOperatorChromeText {

    /// Pill title and colour for a status.
    /// - Parameter status: Mac link state.
    /// - Returns: Short title and background colour.
    static func pill(for status: CameraOperatorMode.MacStatus) -> (title: String, color: UIColor) {
        switch status {
        case .live: return ("● Live on Mac", .systemGreen.withAlphaComponent(0.85))
        case .connecting: return ("Connecting to Mac…", .systemOrange.withAlphaComponent(0.85))
        case .reconnecting: return ("Reconnecting to Mac…", .systemOrange.withAlphaComponent(0.85))
        case .notConnected, .failed: return ("Not connected to Mac", .systemGray.withAlphaComponent(0.85))
        }
    }

    /// Card text, or nil when the card should hide (connected or connecting).
    /// - Parameter status: Mac link state.
    /// - Returns: Message shown above Scan Mac QR Code.
    static func cardMessage(for status: CameraOperatorMode.MacStatus) -> String? {
        switch status {
        case .live, .connecting, .reconnecting:
            return nil
        case .notConnected:
            return "On the Mac, open Eclipse › Settings › Connect › Phone Camera, then scan its QR code."
        case .failed(let message):
            return message
        }
    }
}
