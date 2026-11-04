//
//  WebAutoScrollSpeedBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Floating pill over the page while Auto Scroll is on: a slider from 0.25× to 3×
/// with the current speed beside it. Slides in quarter steps so the label reads
/// cleanly and matches the menu's choices.
final class WebAutoScrollSpeedBar: UIView {

    static let height: CGFloat = 48
    static let maximumWidth: CGFloat = 360

    /// Called with the snapped speed as the thumb moves.
    var onSpeedChange: ((Double) -> Void)?

    let slider = UISlider()
    let valueLabel = UILabel()

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Self.height / 2
        clipsToBounds = true
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)

        let icon = UIImageView(image: UIImage(systemName: "tortoise.fill"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.7)
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        slider.minimumValue = Float(PrompterScrollEngine.minimumSpeed)
        slider.maximumValue = Float(PrompterScrollEngine.maximumSpeed)
        slider.isContinuous = true
        slider.minimumTrackTintColor = .liveStroke
        slider.accessibilityLabel = "Auto Scroll Speed"
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        let stack = UIStackView(arrangedSubviews: [icon, slider, valueLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20)
        ])
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Moves the thumb and label to `speed` without firing `onSpeedChange`.
    func apply(speed: Double) {
        if !slider.isTracking {
            slider.setValue(Float(speed), animated: false)
        }
        valueLabel.text = WebAutoScroller.speedLabel(speed)
        slider.accessibilityValue = WebAutoScroller.speedLabel(speed)
    }

    /// Nearest quarter step inside the allowed range.
    static func snappedSpeed(_ value: Double) -> Double {
        let step = PrompterStageMetrics.speedStep
        let snapped = (value / step).rounded() * step
        return PrompterStageMetrics.clampedSpeed(snapped)
    }

    @objc private func sliderMoved() {
        let speed = Self.snappedSpeed(Double(slider.value))
        valueLabel.text = WebAutoScroller.speedLabel(speed)
        onSpeedChange?(speed)
    }
}
