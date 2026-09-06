//
//  CountdownClockLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Normalized size and position of the countdown clock on the output canvas.
struct CountdownClockLayout: Codable, Equatable, Hashable {
    /// Horizontal center in 0…1 of the canvas.
    var centerX: Double
    /// Vertical center in 0…1 of the canvas.
    var centerY: Double
    /// Size relative to the default stage clock (`1` is default).
    var scale: Double

    /// Centered stage clock at the default size.
    static let `default` = CountdownClockLayout(
        centerX: 0.5, centerY: 0.5, scale: 1
    )

    static let minScale: Double = 0.2
    static let maxScale: Double = 2.5
    /// Fraction of the canvas shorter side used as the default font size.
    static let defaultFontFraction: CGFloat = 0.58

    /// Clamps scale; position is clamped when applied to a canvas.
    var clampedScale: CountdownClockLayout {
        CountdownClockLayout(
            centerX: centerX,
            centerY: centerY,
            scale: min(max(scale, Self.minScale), Self.maxScale)
        )
    }

    /// Default (scale `1`) font size for `canvas`.
    func defaultFontSize(in canvas: CGSize) -> CGFloat {
        let side = min(canvas.width, canvas.height)
        return max(72, side * Self.defaultFontFraction)
    }

    /// Font size after `scale`, capped so the line still fits the canvas height.
    func fontSize(in canvas: CGSize) -> CGFloat {
        let raw = defaultFontSize(in: canvas) * CGFloat(clampedScale.scale)
        return min(raw, max(canvas.height * 0.92, 1))
    }

    /// Moves the center by `delta` points, keeping the clock on `bounds`.
    func translating(
        by delta: CGPoint,
        text: String,
        in bounds: CGRect
    ) -> CountdownClockLayout {
        guard bounds.width > 0, bounds.height > 0 else { return self }
        let next = CountdownClockLayout(
            centerX: centerX + Double(delta.x / bounds.width),
            centerY: centerY + Double(delta.y / bounds.height),
            scale: scale
        )
        return next.clampedToKeepClockVisible(text: text, in: bounds)
    }

    /// Sets `scale` and keeps the clock on `bounds`.
    func scaling(
        to scale: Double,
        text: String,
        in bounds: CGRect
    ) -> CountdownClockLayout {
        CountdownClockLayout(centerX: centerX, centerY: centerY, scale: scale)
            .clampedToKeepClockVisible(text: text, in: bounds)
    }

    /// Fits `label` into `bounds` for `text`.
    func apply(
        to label: UILabel,
        text: String,
        isExpired: Bool,
        in bounds: CGRect
    ) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: fontSize(in: bounds.size),
            weight: .semibold
        )
        let frame = labelFrame(text: text, font: font, in: bounds)
        label.font = font
        label.text = text
        label.textColor = isExpired ? .systemRed : .white
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = frame.width >= bounds.width - 1
        label.minimumScaleFactor = 0.6
        label.frame = frame
    }

    /// Clock frame inside `bounds`, kept fully on-canvas.
    func labelFrame(text: String, font: UIFont, in bounds: CGRect) -> CGRect {
        let fitted = textSize(text, font: font)
        let width = min(max(ceil(fitted.width) + 8, 1), bounds.width)
        let height = min(max(ceil(fitted.height) + 4, 1), bounds.height)
        var x = CGFloat(centerX) * bounds.width - width / 2
        var y = CGFloat(centerY) * bounds.height - height / 2
        x = min(max(0, x), bounds.width - width)
        y = min(max(0, y), bounds.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Private

    private func clampedToKeepClockVisible(
        text: String,
        in bounds: CGRect
    ) -> CountdownClockLayout {
        let scaled = clampedScale
        guard bounds.width > 0, bounds.height > 0 else { return scaled }
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: scaled.fontSize(in: bounds.size),
            weight: .semibold
        )
        let frame = scaled.labelFrame(text: text, font: font, in: bounds)
        return CountdownClockLayout(
            centerX: Double((frame.midX) / bounds.width),
            centerY: Double((frame.midY) / bounds.height),
            scale: scaled.scale
        )
    }

    private func textSize(_ text: String, font: UIFont) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font])
    }
}

// MARK: - Live Preview

/// In-flight editor layout, applied to AirPlay / hero before Save.
@MainActor
enum CountdownClockLayoutPreview {
    static let didChangeNotification = Notification.Name(
        "CountdownClockLayoutPreview.didChange"
    )

    private(set) static var current: (id: UUID, layout: CountdownClockLayout)?

    /// Draft layout for `id`, or the saved layout, or default.
    static func resolved(for id: UUID) -> CountdownClockLayout {
        if let current, current.id == id { return current.layout }
        return CountdownStore.shared.countdown(id: id)?.layout ?? .default
    }

    /// Publishes a draft for `id`, or clears it when `layout` is nil.
    static func set(_ layout: CountdownClockLayout?, for id: UUID) {
        if let layout {
            current = (id, layout)
        } else if current?.id == id {
            current = nil
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
