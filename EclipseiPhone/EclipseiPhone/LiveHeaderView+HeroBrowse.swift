//
//  LiveHeaderView+HeroBrowse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Hero Swipe Browse

extension LiveHeaderView {

    /// Installs the left/right swipes that browse from the hero.
    ///
    /// One pair of recognizers serves both modes: a live Slideshow advances its
    /// own slides, otherwise the swipe walks the open Show's stills. The host
    /// controller keeps the two flags mutually exclusive; Slideshow wins if both
    /// are ever set, since it owns the hero while it runs.
    func installHeroBrowseGestures() {
        let left = UISwipeGestureRecognizer(
            target: self, action: #selector(handleHeroSwipeLeft)
        )
        left.direction = .left
        addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(
            target: self, action: #selector(handleHeroSwipeRight)
        )
        right.direction = .right
        addGestureRecognizer(right)

        browseSwipeRecognizers = [left, right]
    }

    /// Routes a recognized swipe to whichever browse mode is enabled.
    func dispatchHeroBrowse(delta: Int) {
        if allowsSlideshowBrowse {
            onSlideshowSwipe?(delta)
            return
        }
        guard allowsLibraryBrowse else { return }
        onLibraryBrowse?(delta)
    }

    // MARK: - Private

    @objc private func handleHeroSwipeLeft() {
        dispatchHeroBrowse(delta: 1)
    }

    @objc private func handleHeroSwipeRight() {
        dispatchHeroBrowse(delta: -1)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension LiveHeaderView: UIGestureRecognizerDelegate {

    /// Keeps the hero's tap-to-open gesture off its own chrome.
    ///
    /// A recognized tap cancels touches in the view, so without this a press on
    /// Flip Camera / Screen Fit / the ribbon toggle would open the camera
    /// controller or fullscreen Preview instead of running the control.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let view = touch.view else { return true }
        return !(view is UIControl)
    }
}
