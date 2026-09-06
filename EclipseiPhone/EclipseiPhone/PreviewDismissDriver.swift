//
//  PreviewDismissDriver.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Adds drag-down-to-close to a fullscreen Preview.
///
/// This supplements the header's Close button rather than replacing it: the gesture
/// is invisible, and VoiceOver and Switch Control need a focusable control to leave
/// the screen with.
///
/// Attach from `viewDidLoad` and keep a strong reference — `transitioningDelegate`
/// is weak, so the host owning the driver is what keeps the transition alive.
@MainActor
final class PreviewDismissDriver: NSObject {

    /// Set `false` while the page is zoomed, so a drag pans the image instead.
    var isEnabled = true

    /// Fires while a drag owns the screen, so the host can stop horizontal paging
    /// for the duration and resume once the card settles.
    var onDraggingChanged: ((Bool) -> Void)?

    private weak var host: UIViewController?
    private let pan = UIPanGestureRecognizer()
    private var activeTransition: PreviewDismissTransition?

    /// - Parameter host: Preview controller to dismiss; its view gains the gesture.
    init(host: UIViewController) {
        self.host = host
        super.init()
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        pan.addTarget(self, action: #selector(handlePan(_:)))
        host.view.addGestureRecognizer(pan)
        host.transitioningDelegate = self
    }

    // MARK: - Drag

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        switch gesture.state {
        case .began:
            beginDrag()
        case .changed:
            activeTransition?.update(translation: translation)
        case .ended:
            endDrag(translation: translation, velocity: gesture.velocity(in: gesture.view).y)
        case .cancelled, .failed:
            settleOrClear { $0.cancel() }
        default:
            break
        }
    }

    private func beginDrag() {
        let transition = PreviewDismissTransition()
        transition.onSettled = { [weak self] _ in
            self?.activeTransition = nil
            self?.onDraggingChanged?(false)
        }
        activeTransition = transition
        onDraggingChanged?(true)
        // Kicks UIKit into asking us for the animator and interaction controller
        // below, which is what hands the transition its context.
        host?.dismiss(animated: true)
    }

    private func endDrag(translation: CGPoint, velocity: CGFloat) {
        let offset = PreviewDismissGeometry.cardOffset(for: translation)
        let progress = PreviewDismissGeometry.progress(forVerticalOffset: offset.y)
        let complete = PreviewDismissGeometry.shouldComplete(
            progress: progress, verticalVelocity: velocity
        )
        settleOrClear { complete ? $0.finish(velocity: velocity) : $0.cancel() }
    }

    /// Runs `settle` only when a transition context actually arrived. Without the
    /// guard a dismissal UIKit refused would strand the driver mid-drag, leaving
    /// paging switched off for good.
    private func settleOrClear(_ settle: (PreviewDismissTransition) -> Void) {
        guard let transition = activeTransition else { return }
        guard transition.isRunning else {
            activeTransition = nil
            onDraggingChanged?(false)
            return
        }
        settle(transition)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PreviewDismissDriver: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isEnabled, activeTransition == nil, let host,
              host.presentedViewController == nil, !host.isBeingDismissed else { return false }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        // Downward-dominant only: sideways travel belongs to the gallery pager, and
        // an upward drag has nowhere to go.
        let velocity = pan.velocity(in: pan.view)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    /// The pager's scroll view may already be tracking the touch. Recognizing
    /// alongside it lets the drag start anyway; `onDraggingChanged` then switches
    /// paging off, which cancels the scroll view's pan.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension PreviewDismissDriver: UIViewControllerTransitioningDelegate {

    /// Non-nil only while a drag is driving, so tapping Close keeps the stock
    /// cover-vertical dismissal.
    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        activeTransition
    }

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        activeTransition
    }
}
