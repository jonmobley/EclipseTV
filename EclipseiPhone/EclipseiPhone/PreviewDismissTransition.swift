//
//  PreviewDismissTransition.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Runs the drag-to-dismiss animation for a fullscreen Preview.
///
/// Preview stays `.fullScreen`, so the screen that opened it is torn out of the
/// hierarchy while it is up and UIKit only hands it back for the length of the
/// transition. That is why this inserts the `to` view itself, with a dimming layer
/// between: the grid is revealed *by* the drag rather than sitting behind it the
/// whole time, and the presenting screen keeps its normal appearance callbacks.
///
/// Geometry lives in `PreviewDismissGeometry`.
@MainActor
final class PreviewDismissTransition: NSObject {

    /// Called once the card has settled, whether it closed or sprang back.
    var onSettled: ((_ dismissed: Bool) -> Void)?

    /// True once UIKit has handed over a transition context to drive.
    var isRunning: Bool { context != nil }

    private var context: UIViewControllerContextTransitioning?
    private var card: UIView?
    private var isInteractive = false
    private var offset: CGPoint = .zero
    private let dimming = UIView()

    // MARK: - Drag

    /// Tracks the finger. Safe to call before the transition context has arrived.
    func update(translation: CGPoint) {
        guard let card, let context else { return }
        offset = PreviewDismissGeometry.cardOffset(for: translation)
        let progress = PreviewDismissGeometry.progress(forVerticalOffset: offset.y)
        let scale = PreviewDismissGeometry.scale(at: progress)
        card.transform = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
        card.layer.cornerRadius = PreviewDismissGeometry.cornerRadius(at: progress)
        dimming.alpha = PreviewDismissGeometry.dimAlpha(at: progress)
        context.updateInteractiveTransition(progress)
    }

    /// Sends the card the rest of the way out and completes the dismissal.
    func finish(velocity: CGFloat) {
        guard let context, let card else { return }
        let remaining = max(context.containerView.bounds.height - offset.y, 1)
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: max(velocity, 0) / remaining,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            let scale = PreviewDismissGeometry.minimumScale
            card.transform = CGAffineTransform(
                translationX: self.offset.x,
                y: context.containerView.bounds.height
            ).scaledBy(x: scale, y: scale)
            self.dimming.alpha = 0
        } completion: { _ in
            // Leave the card transformed: UIKit pulls it out of the container on
            // completion, and resetting first flashes it back to fullscreen.
            self.dimming.removeFromSuperview()
            if self.isInteractive { context.finishInteractiveTransition() }
            context.completeTransition(true)
            self.reset(dismissed: true)
        }
    }

    /// Springs the card back and leaves Preview on screen.
    func cancel() {
        guard let context, let card else { return }
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            card.transform = .identity
            card.layer.cornerRadius = 0
            self.dimming.alpha = PreviewDismissGeometry.restingDim
        } completion: { _ in
            card.clipsToBounds = false
            self.dimming.removeFromSuperview()
            if self.isInteractive { context.cancelInteractiveTransition() }
            context.completeTransition(false)
            self.reset(dismissed: false)
        }
    }

    // MARK: - Setup

    private func prepare(_ transitionContext: UIViewControllerContextTransitioning) {
        context = transitionContext
        let container = transitionContext.containerView
        guard let fromView = transitionContext.view(forKey: .from)
                ?? transitionContext.viewController(forKey: .from)?.view else { return }
        card = fromView

        if let toController = transitionContext.viewController(forKey: .to),
           let toView = transitionContext.view(forKey: .to) ?? toController.viewIfLoaded {
            toView.frame = transitionContext.finalFrame(for: toController)
            container.insertSubview(toView, at: 0)
        }

        dimming.backgroundColor = .black
        dimming.alpha = PreviewDismissGeometry.restingDim
        dimming.frame = container.bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.insertSubview(dimming, belowSubview: fromView)

        fromView.clipsToBounds = true
        fromView.layer.applyContinuousCorner(radius: 0)
    }

    private func reset(dismissed: Bool) {
        context = nil
        card = nil
        offset = .zero
        isInteractive = false
        onSettled?(dismissed)
    }
}

// MARK: - UIViewControllerAnimatedTransitioning

extension PreviewDismissTransition: UIViewControllerAnimatedTransitioning {

    func transitionDuration(
        using transitionContext: UIViewControllerContextTransitioning?
    ) -> TimeInterval {
        0.32
    }

    /// Non-interactive path: the drag ended before UIKit started the transition, so
    /// play the same exit without a finger driving it.
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        prepare(transitionContext)
        finish(velocity: 0)
    }
}

// MARK: - UIViewControllerInteractiveTransitioning

extension PreviewDismissTransition: UIViewControllerInteractiveTransitioning {

    func startInteractiveTransition(
        _ transitionContext: UIViewControllerContextTransitioning
    ) {
        isInteractive = true
        prepare(transitionContext)
    }
}
