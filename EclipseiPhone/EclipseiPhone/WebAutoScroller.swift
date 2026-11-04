//
//  WebAutoScroller.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Scrolls the phone browser's page down by itself at a chosen speed.
///
/// It moves the page's own scroll view, so the existing scroll mirroring carries
/// the position to AirPlay / HDMI. Stops at the bottom, when the user drags, and
/// when the page or tab changes. Speed is a per-device setting shared with the
/// Prompter's scale (40 pt/s × multiplier).
@MainActor
final class WebAutoScroller {

    static let speedKey = "EclipseTV.web.autoScrollSpeed"

    /// Choices offered in the speed menu.
    static let speedOptions: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]

    /// Where the page's scroll view comes from (the active tab's web view).
    var scrollViewProvider: () -> UIScrollView?

    /// Called when running state or speed changes, for the chrome to repaint.
    var onChange: (() -> Void)?

    private(set) var isRunning = false
    private(set) var speed: Double

    private let defaults: UserDefaults
    private let frames: PrompterFrameSource

    init(
        defaults: UserDefaults = .standard,
        frames: PrompterFrameSource? = nil,
        scrollView: @escaping () -> UIScrollView? = { nil }
    ) {
        self.defaults = defaults
        self.frames = frames ?? DisplayLinkFrameSource()
        self.scrollViewProvider = scrollView
        let stored = defaults.object(forKey: Self.speedKey) as? Double
        self.speed = PrompterStageMetrics.clampedSpeed(stored ?? PrompterScrollEngine.defaultSpeed)
        self.frames.onFrame = { [weak self] dt in self?.tick(deltaTime: dt) }
    }

    /// Whether there is anything below the fold to scroll to.
    var canScroll: Bool {
        guard let scroll = scrollViewProvider() else { return false }
        return Self.maxOffsetY(of: scroll) - scroll.contentOffset.y > 0.5
    }

    func start() {
        guard !isRunning, canScroll else { return }
        isRunning = true
        frames.start()
        onChange?()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        frames.stop()
        onChange?()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func setSpeed(_ multiplier: Double) {
        let next = PrompterStageMetrics.clampedSpeed(multiplier)
        guard next != speed else { return }
        speed = next
        defaults.set(next, forKey: Self.speedKey)
        onChange?()
    }

    /// One frame. Public so tests can step time by hand.
    func tick(deltaTime: TimeInterval) {
        guard isRunning, let scroll = scrollViewProvider() else {
            stop()
            return
        }
        let maxY = Self.maxOffsetY(of: scroll)
        let step = CGFloat(deltaTime) * PrompterScrollEngine.basePointsPerSecond * CGFloat(speed)
        let next = min(scroll.contentOffset.y + step, maxY)
        if next != scroll.contentOffset.y {
            scroll.contentOffset = CGPoint(x: scroll.contentOffset.x, y: next)
        }
        if next >= maxY { stop() }
    }

    /// Furthest the page scrolls, matching how progress is mirrored to the display.
    static func maxOffsetY(of scroll: UIScrollView) -> CGFloat {
        max(0, scroll.contentSize.height - scroll.bounds.height)
    }

    /// `1×`, `1.5×`, `0.75×` for menus.
    static func speedLabel(_ multiplier: Double) -> String {
        PrompterViewController.speedText(multiplier)
    }
}
