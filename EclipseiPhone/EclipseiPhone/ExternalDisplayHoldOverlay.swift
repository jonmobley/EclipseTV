//
//  ExternalDisplayHoldOverlay.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Freeze and White on the external (AirPlay / cable) screen.
///
/// Both are views laid over the external window, above whatever the presentation
/// controller is drawing, so the picture underneath can keep changing (and a
/// video keeps playing, silently hidden) while the audience sees a still frame
/// or a white screen. Removing the overlay shows whatever is live now.
///
/// Thread safety: main thread only (UIKit views).
@MainActor
final class ExternalDisplayHoldOverlay {

    // MARK: Constants

    /// Shared instance driven by the grid.
    static let shared = ExternalDisplayHoldOverlay()

    /// Fade when an overlay comes or goes. Short: a projector should not linger.
    private static let fadeDuration: TimeInterval = 0.12

    // MARK: Properties

    private var freezeView: UIView?
    private var whiteView: UIView?

    /// A still of the external screen is on top.
    var isFreezeShown: Bool { freezeView != nil }
    /// The white screen is on top.
    var isWhiteShown: Bool { whiteView != nil }

    private init() {}

    // MARK: Freeze

    /// Covers the external window with a snapshot of what it shows right now.
    /// - Parameter window: The external display's window.
    /// - Returns: False when no snapshot could be taken (nothing frozen).
    @discardableResult
    func showFreeze(on window: UIWindow?) -> Bool {
        guard freezeView == nil, let window else { return freezeView != nil }
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        let still = UIImageView(image: image)
        still.frame = bounds
        still.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        still.isUserInteractionEnabled = false
        still.backgroundColor = .black
        window.addSubview(still)
        freezeView = still
        stack(on: window)
        return true
    }

    /// Removes the still; the live picture is visible again.
    func hideFreeze() {
        remove(freezeView)
        freezeView = nil
    }

    // MARK: White

    /// Covers the external window with solid white.
    /// - Parameter window: The external display's window.
    func showWhite(on window: UIWindow?) {
        guard whiteView == nil, let window else { return }
        let white = UIView(frame: window.bounds)
        white.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        white.backgroundColor = .white
        white.isUserInteractionEnabled = false
        white.alpha = 0
        window.addSubview(white)
        whiteView = white
        UIView.animate(withDuration: Self.fadeDuration) { white.alpha = 1 }
        stack(on: window)
    }

    /// Removes the white cover.
    func hideWhite() {
        remove(whiteView)
        whiteView = nil
    }

    // MARK: Lifecycle

    /// Forgets both overlays without animating (the window is going away).
    func reset() {
        freezeView?.removeFromSuperview()
        whiteView?.removeFromSuperview()
        freezeView = nil
        whiteView = nil
    }

    // MARK: Helpers

    /// White always sits above a frozen still.
    private func stack(on window: UIWindow) {
        if let freezeView { window.bringSubviewToFront(freezeView) }
        if let whiteView { window.bringSubviewToFront(whiteView) }
    }

    private func remove(_ view: UIView?) {
        guard let view else { return }
        UIView.animate(
            withDuration: Self.fadeDuration,
            animations: { view.alpha = 0 },
            completion: { _ in view.removeFromSuperview() }
        )
    }
}
