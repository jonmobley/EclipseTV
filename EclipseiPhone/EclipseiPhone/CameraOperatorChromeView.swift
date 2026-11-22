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
/// - Status pill: whether the picture is reaching the Mac (where Back sits).
/// - Connect card: shown until the Mac is connected, with Scan Mac QR Code.
///
/// Touches outside these controls fall through to the camera underneath, so
/// pinch-to-zoom, Flip, frames and stills keep working. Main thread only.
final class CameraOperatorChromeView: UIView {

    // MARK: - Constants

    private static let pillHeight: CGFloat = 30
    private static let cardWidth: CGFloat = 300

    // MARK: - Callbacks

    /// Invoked by Scan Mac QR Code.
    var onScan: (() -> Void)?

    // MARK: - Subviews

    private let statusPill = UILabel()
    private let card = UIView()
    private let cardLabel = UILabel()
    private let scanButton = UIButton(type: .system)

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStatusPill()
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
    ///   - topRowFrame: Where Back normally sits; the pill is centred on that row.
    func layout(panel: CGRect, topRowFrame: CGRect) {
        frame = superview?.bounds ?? frame
        let pillWidth = statusPill.intrinsicContentSize.width
        statusPill.frame = CGRect(
            x: panel.midX - pillWidth / 2,
            y: topRowFrame.midY - Self.pillHeight / 2,
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
        !card.isHidden && card.frame.contains(point)
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
