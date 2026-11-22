//
//  CameraOperatorChromeView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - CameraOperatorChromeView

/// Camera Mode's Mac status pill, laid over the full-screen Camera.
///
/// Hidden until the volunteer links a Mac (Connect to Mac in the camera
/// settings); then it shows Linked, or Live while the Mac has this camera on
/// its Audience Display. Touches always fall through to the camera. Main
/// thread only.
final class CameraOperatorChromeView: UIView {

    // MARK: - Constants

    private static let pillHeight: CGFloat = 30

    // MARK: - Subviews

    private let statusPill = UILabel()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStatusPill()
        apply(status: CameraOperatorMode.shared.macStatus)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Public Interface

    /// Updates the pill for a Mac link state.
    /// - Parameter status: Current Camera Mode Mac status.
    func apply(status: CameraOperatorMode.MacStatus) {
        guard let text = CameraOperatorChromeText.pill(for: status) else {
            statusPill.isHidden = true
            return
        }
        statusPill.isHidden = false
        statusPill.text = "  \(text.title)  "
        statusPill.backgroundColor = text.color
        statusPill.accessibilityLabel = text.title
        setNeedsLayout()
    }

    /// Centres the pill over the panel on the top control row.
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
    }

    // MARK: - Touch Pass-Through

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
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
}

// MARK: - CameraOperatorChromeText

/// Words and colours for Camera Mode's Mac status (pure, testable).
enum CameraOperatorChromeText {

    /// Pill title and colour, or nil when no pill shows (no Mac link).
    /// - Parameter status: Mac link state.
    static func pill(for status: CameraOperatorMode.MacStatus) -> (title: String, color: UIColor)? {
        switch status {
        case .off: return nil
        case .live: return ("● Live", .systemRed.withAlphaComponent(0.9))
        case .linked: return ("Linked", .systemBlue.withAlphaComponent(0.85))
        case .connecting: return ("Connecting to Mac…", .systemOrange.withAlphaComponent(0.85))
        case .reconnecting: return ("Reconnecting to Mac…", .systemOrange.withAlphaComponent(0.85))
        case .failed: return ("Mac Disconnected", .systemGray.withAlphaComponent(0.85))
        }
    }

    /// Short status line for the camera settings' Mac section.
    /// - Parameter status: Mac link state.
    static func settingsStatus(for status: CameraOperatorMode.MacStatus) -> String {
        switch status {
        case .off: return "Not linked"
        case .connecting: return "Connecting…"
        case .linked: return "Linked"
        case .live: return "Live on the Audience Display"
        case .reconnecting: return "Reconnecting…"
        case .failed: return "Disconnected"
        }
    }

    /// Footer under the settings' Mac section.
    /// - Parameter status: Mac link state.
    static func settingsFooter(for status: CameraOperatorMode.MacStatus) -> String {
        switch status {
        case .off:
            return "Send this camera to Eclipse on a Mac. On the Mac, open Settings › Connect › "
                + "Phone Camera, then scan its QR code."
        case .failed(let message):
            return message
        case .connecting, .linked, .live, .reconnecting:
            return "Live means the Mac is showing this camera on its Audience Display."
        }
    }
}
