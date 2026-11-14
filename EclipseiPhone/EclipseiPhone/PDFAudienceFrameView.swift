//
//  PDFAudienceFrameView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Overlay for the phone PDF reader that marks what the audience sees: the page
/// outside the frame is dimmed, and the frame itself gets a thin outline.
///
/// Purely visual: it never takes touches, so drags pass through to the stage.
final class PDFAudienceFrameView: UIView {

    /// How dark the page outside the frame gets (0 = untouched, 1 = black).
    static let dimAlpha: CGFloat = 0.6
    static let outlineWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 4

    /// The audience frame in this view's coordinates.
    var frameRect: CGRect = .zero {
        didSet {
            guard frameRect != oldValue else { return }
            setNeedsLayout()
        }
    }

    private let dimLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(Self.dimAlpha).cgColor
        layer.addSublayer(dimLayer)

        outlineLayer.fillColor = UIColor.clear.cgColor
        outlineLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        outlineLayer.lineWidth = Self.outlineWidth
        layer.addSublayer(outlineLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        outlineLayer.frame = bounds
        guard frameRect.width > 0, frameRect.height > 0 else {
            dimLayer.path = nil
            outlineLayer.path = nil
            CATransaction.commit()
            return
        }
        let hole = UIBezierPath(roundedRect: frameRect, cornerRadius: Self.cornerRadius)
        let dim = UIBezierPath(rect: bounds)
        dim.append(hole)
        dimLayer.path = dim.cgPath
        // Outline sits just outside the frame so it never covers the page edge.
        let half = Self.outlineWidth / 2
        outlineLayer.path = UIBezierPath(
            roundedRect: frameRect.insetBy(dx: -half, dy: -half),
            cornerRadius: Self.cornerRadius + half
        ).cgPath
        CATransaction.commit()
    }
}

/// Reader stage that hands touches outside the audience frame to the framed
/// PDF's scroll view, so a drag or pinch anywhere on the dimmed page moves what
/// the audience sees (the context view behind it is display-only).
final class PDFReaderStageView: UIView {

    /// The audience frame in this view's coordinates.
    var panelRect: CGRect = .zero

    /// Receives touches that land outside `panelRect`.
    weak var forwardingTarget: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard let hit, !panelRect.contains(point), let target = forwardingTarget,
              target.window != nil,
              hit === self else { return hit }
        return target
    }
}
