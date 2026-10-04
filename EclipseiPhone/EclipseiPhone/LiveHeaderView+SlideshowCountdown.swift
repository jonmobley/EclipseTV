//
//  LiveHeaderView+SlideshowCountdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Slideshow Autoplay Countdown

extension LiveHeaderView {

    /// Shows the seconds left until Autoplay advances, bottom-trailing on the hero.
    ///
    /// - Parameters:
    ///   - deadline: When the next slide goes live; nil hides the ring.
    ///   - interval: Full countdown length, so the ring can show how much is left.
    func setSlideshowCountdown(deadline: Date?, interval: TimeInterval) {
        guard let deadline, interval > 0 else {
            slideshowCountdownRing?.removeFromSuperview()
            slideshowCountdownRing = nil
            slideshowCountdownTrailing = nil
            return
        }
        if slideshowCountdownRing == nil {
            installSlideshowCountdownRing()
        }
        slideshowCountdownRing?.start(deadline: deadline, interval: interval)
        layoutSlideshowCountdownRing()
    }

    /// Sits beside the Fit / Fill circle when it's shown, else in the corner.
    func layoutSlideshowCountdownRing() {
        guard let ring = slideshowCountdownRing else { return }
        slideshowCountdownTrailing?.constant = screenFitButton == nil ? -10 : -54
        bringSubviewToFront(ring)
    }

    // MARK: - Private

    private func installSlideshowCountdownRing() {
        let ring = SlideshowCountdownRingView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ring)
        let trailing = ring.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 36),
            ring.heightAnchor.constraint(equalToConstant: 36),
            trailing,
            ring.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        ring.alpha = screenFitButton?.alpha ?? 1
        ring.isHidden = screenFitButton?.isHidden ?? false
        slideshowCountdownRing = ring
        slideshowCountdownTrailing = trailing
    }
}

// MARK: - Ring View

/// Small dark circle with the seconds left inside and a white arc that
/// sweeps away clockwise from 12 o'clock as the slide's time runs out.
///
/// Driven by a display link against a wall-clock deadline, so it stays
/// correct across manual slide changes and app backgrounding.
final class SlideshowCountdownRingView: UIView {

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let label = UILabel()
    private var displayLink: CADisplayLink?
    private var deadline = Date()
    private var interval: TimeInterval = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        layer.cornerRadius = 18

        for shape in [trackLayer, progressLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 2.5
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        progressLayer.strokeColor = UIColor.white.cgColor

        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Next slide in"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 4
        let radius = min(bounds.width, bounds.height) / 2 - inset
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // Starts at 12 o'clock and runs clockwise.
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 1.5 * .pi,
            clockwise: true
        ).cgPath
        trackLayer.path = path
        progressLayer.path = path
        trackLayer.frame = bounds
        progressLayer.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else {
            startDisplayLink()
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    /// Restarts the countdown for a new slide.
    func start(deadline: Date, interval: TimeInterval) {
        self.deadline = deadline
        self.interval = max(interval, 0.001)
        tick()
        if window != nil { startDisplayLink() }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let remaining = max(0, deadline.timeIntervalSinceNow)
        let elapsedFraction = CGFloat(min(1, 1 - remaining / interval))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Trimming the start eats the arc clockwise, leaving what's left.
        progressLayer.strokeStart = elapsedFraction
        CATransaction.commit()
        let seconds = Int(ceil(remaining))
        let text = "\(max(seconds, 0))"
        if label.text != text {
            label.text = text
            accessibilityValue = "\(seconds) seconds"
        }
    }
}
