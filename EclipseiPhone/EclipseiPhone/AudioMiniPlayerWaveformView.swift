//
//  AudioMiniPlayerWaveformView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Equalizer bars drawn in the Music bubble while a track is playing.
final class AudioMiniPlayerWaveformView: UIView {

    private static let barCount = 3
    private static let barWidth: CGFloat = 4
    private static let barSpacing: CGFloat = 3.5
    private static let durations: [CFTimeInterval] = [0.5, 0.64, 0.44]
    private static let restScales: [CGFloat] = [0.42, 0.7, 0.5]
    private static let peakScales: [CGFloat] = [0.86, 1.0, 0.78]

    private var bars: [CALayer] = []
    private(set) var isPlaying = false
    /// Number of equalizer bars (always 3).
    var barCount: Int { bars.count }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        bars = (0..<Self.barCount).map { _ in
            let bar = CALayer()
            bar.backgroundColor = UIColor.white.cgColor
            bar.cornerRadius = 2
            bar.anchorPoint = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(bar)
            return bar
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows bars while playing; animates unless Reduce Motion is on.
    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else {
            if playing { layoutBars() }
            return
        }
        isPlaying = playing
        isHidden = !playing
        if playing {
            layoutBars()
            startOrFreezeAnimations()
        } else {
            stopAnimations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutBars()
    }

    var hasWaveAnimations: Bool {
        bars.contains { $0.animation(forKey: "wave") != nil }
    }

    // MARK: - Private

    private func layoutBars() {
        let count = CGFloat(Self.barCount)
        let total = count * Self.barWidth + (count - 1) * Self.barSpacing
        let originX = (bounds.width - total) / 2
        let height = max(bounds.height * 0.82, 1)
        let bottom = bounds.midY + height / 2
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: height)
            bar.position = CGPoint(
                x: originX + CGFloat(index) * (Self.barWidth + Self.barSpacing)
                    + Self.barWidth / 2,
                y: bottom
            )
            if bar.animation(forKey: "wave") == nil {
                bar.transform = CATransform3DMakeScale(1, Self.restScales[index], 1)
            }
        }
    }

    private func startOrFreezeAnimations() {
        stopAnimations()
        let animate = !UIAccessibility.isReduceMotionEnabled && UIView.areAnimationsEnabled
        for (index, bar) in bars.enumerated() {
            bar.transform = CATransform3DMakeScale(1, Self.restScales[index], 1)
            guard animate else { continue }
            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = Self.restScales[index]
            anim.toValue = Self.peakScales[index]
            anim.duration = Self.durations[index]
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.timeOffset = CFTimeInterval(index) * 0.11
            bar.add(anim, forKey: "wave")
        }
    }

    private func stopAnimations() {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "wave")
            bar.transform = CATransform3DMakeScale(1, Self.restScales[index], 1)
        }
    }
}
