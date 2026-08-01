//
//  LiveHeaderView+SlideshowBrowse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Slideshow Swipe

extension LiveHeaderView {

    /// Installs left/right swipes that call `onSlideshowSwipe` (±1).
    func installSlideshowBrowseGestures() {
        let left = UISwipeGestureRecognizer(
            target: self, action: #selector(slideshowSwipeLeft)
        )
        left.direction = .left
        addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(
            target: self, action: #selector(slideshowSwipeRight)
        )
        right.direction = .right
        addGestureRecognizer(right)
    }

    @objc private func slideshowSwipeLeft() {
        guard allowsSlideshowBrowse else { return }
        onSlideshowSwipe?(1)
    }

    @objc private func slideshowSwipeRight() {
        guard allowsSlideshowBrowse else { return }
        onSlideshowSwipe?(-1)
    }
}
