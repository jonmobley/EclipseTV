//
//  AudioMiniVolumeBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Fill-from-bottom volume track; drag or tap to set the mix level.
final class AudioMiniVolumeBar: UIView {

    var value: Float = 1 {
        didSet {
            let clamped = min(1, max(0, value))
            if clamped != value {
                value = clamped
                return
            }
            setNeedsLayout()
        }
    }

    var onChanged: ((Float) -> Void)?
    var onEnded: (() -> Void)?

    private let fill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Volume"
        accessibilityTraits = .adjustable
        backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.18)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        fill.backgroundColor = .systemBlue
        fill.isUserInteractionEnabled = false
        addSubview(fill)

        let press = UILongPressGestureRecognizer(
            target: self, action: #selector(handlePress(_:))
        )
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height * CGFloat(value)
        fill.frame = CGRect(
            x: 0, y: bounds.height - height, width: bounds.width, height: height
        )
    }

    override var accessibilityValue: String? {
        get { "\(Int((value * 100).rounded())) percent" }
        set {}
    }

    override func accessibilityIncrement() {
        applyValue(min(1, value + 0.1), ended: true)
    }

    override func accessibilityDecrement() {
        applyValue(max(0, value - 0.1), ended: true)
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        applyValue(value(at: gesture.location(in: self)), ended: false)
        if gesture.state == .ended || gesture.state == .cancelled {
            onEnded?()
        }
    }

    private func value(at point: CGPoint) -> Float {
        let height = max(bounds.height, 1)
        return min(1, max(0, Float(1 - point.y / height)))
    }

    private func applyValue(_ next: Float, ended: Bool) {
        value = next
        onChanged?(value)
        if ended { onEnded?() }
    }
}
