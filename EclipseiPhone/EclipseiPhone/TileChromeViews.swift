//
//  TileChromeViews.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - PaddedLabel

/// A label with internal padding, used for the duration pill.
final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

// MARK: - GradientView

/// Vertical `CAGradientLayer` host for caption readability scrims.
final class GradientView: UIView {
    var colors: [UIColor] = [] {
        didSet { updateColors() }
    }
    var locations: [NSNumber] = [0, 1] {
        didSet { gradient.locations = locations }
    }

    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Clear→black must composite over the thumbnail; opaque skips that blend.
        isOpaque = false
        backgroundColor = .clear
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    private func updateColors() {
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = locations
    }
}
