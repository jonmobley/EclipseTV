//
//  LiveHeaderView+OverlayAdjust.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Drag and pinch a live overlay (template card, photo or video
//               overlay) on the hero to move and resize it, like dragging it on
//               the Mac's preview. The TV follows the fingers; the new spot and
//               size are saved when they lift. See `OverlayAdjustSession`.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

// MARK: - Overlay Adjust

extension LiveHeaderView {

    /// Extra points around a small card that still pick it up.
    private static let overlayTouchSlop: CGFloat = 12
    /// A pinch's center may sit a bit further out: fingers straddle the card.
    private static let overlayPinchSlop: CGFloat = 32

    /// Installs the overlay drag and pinch. Browse swipes and other hero drags
    /// wait for the drag to fail, which it does at once off an overlay.
    ///
    /// The two never run at once (like the still / countdown adjust): a drag that
    /// gains a second finger stays a drag, and the pinch alone carries two-finger
    /// moves, so a gesture is never saved halfway or moved twice.
    func installOverlayAdjustGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleOverlayAdjustPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        overlayAdjustPan = pan

        let pinch = UIPinchGestureRecognizer(
            target: self, action: #selector(handleOverlayAdjustPinch(_:))
        )
        pinch.delegate = self
        addGestureRecognizer(pinch)
        overlayAdjustPinch = pinch

        for swipe in browseSwipeRecognizers {
            swipe.require(toFail: pan)
        }
        directAdjustPan?.require(toFail: pan)
        directAdjustPinch?.require(toFail: pinch)
    }

    /// Whether `gesture` lands on a live overlay that may be adjusted now.
    func overlayAdjustShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard allowsOverlayAdjust, !isCompactPresentation else { return false }
        if overlayAdjustSession != nil { return true }
        return overlayHit(for: gesture) != nil
    }

    /// Drops an unfinished adjustment (e.g. adjusting was switched off mid-drag).
    func cancelOverlayAdjust() {
        guard let session = overlayAdjustSession else { return }
        overlayAdjustSession = nil
        onAdjustOverlay?(session.original, true)
    }

    // MARK: - Private

    private func overlayHit(
        for gesture: UIGestureRecognizer
    ) -> (overlay: RenderedOverlay, frame: CGRect, contentFrame: CGRect)? {
        let slop = gesture is UIPinchGestureRecognizer
            ? Self.overlayPinchSlop : Self.overlayTouchSlop
        return liveOverlayHost.overlay(at: gesture.location(in: liveOverlayHost), slop: slop)
    }

    @objc private func handleOverlayAdjustPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginOverlayAdjustIfNeeded(gesture)
            gesture.setTranslation(.zero, in: liveOverlayHost)
        case .changed:
            let delta = gesture.translation(in: liveOverlayHost)
            gesture.setTranslation(.zero, in: liveOverlayHost)
            overlayAdjustSession?.move(by: delta)
            renderOverlayAdjust()
        case .ended, .cancelled, .failed:
            finishOverlayAdjustIfIdle()
        default:
            break
        }
    }

    @objc private func handleOverlayAdjustPinch(_ gesture: UIPinchGestureRecognizer) {
        let location = gesture.location(in: liveOverlayHost)
        switch gesture.state {
        case .began:
            beginOverlayAdjustIfNeeded(gesture)
            overlayAdjustPinchLocation = (location, gesture.numberOfTouches)
            gesture.scale = 1
        case .changed:
            // The fingers' centre moving carries the overlay too, both while two
            // fingers pinch and once one has lifted (the other keeps dragging, as
            // in the still / countdown adjust). A finger lifting or landing jumps
            // the centre, so the frame where the count changes only re-anchors.
            let touches = gesture.numberOfTouches
            if let last = overlayAdjustPinchLocation, last.touches == touches {
                overlayAdjustSession?.move(by: CGPoint(
                    x: location.x - last.point.x, y: location.y - last.point.y
                ))
            }
            overlayAdjustPinchLocation = (location, touches)
            overlayAdjustSession?.scale(by: gesture.scale)
            gesture.scale = 1
            renderOverlayAdjust()
        case .ended, .cancelled, .failed:
            overlayAdjustPinchLocation = nil
            finishOverlayAdjustIfIdle()
        default:
            break
        }
    }

    private func beginOverlayAdjustIfNeeded(_ gesture: UIGestureRecognizer) {
        guard overlayAdjustSession == nil, let hit = overlayHit(for: gesture) else { return }
        overlayAdjustSession = OverlayAdjustSession(
            overlay: hit.overlay, frame: hit.frame, contentFrame: hit.contentFrame
        )
        _ = overlayAdjustSession?.refreshSnap()
        Haptics.impactLight()
    }

    /// Shows the in-flight position on the hero and the TV.
    private func renderOverlayAdjust() {
        guard var session = overlayAdjustSession else { return }
        if session.refreshSnap() { Haptics.selection() }
        overlayAdjustSession = session
        onAdjustOverlay?(session.overlay, false)
    }

    /// Saves once no adjusting finger is left on the hero.
    private func finishOverlayAdjustIfIdle() {
        let active: [UIGestureRecognizer.State] = [.began, .changed]
        if let pan = overlayAdjustPan, active.contains(pan.state) { return }
        if let pinch = overlayAdjustPinch, active.contains(pinch.state) { return }
        guard let session = overlayAdjustSession else { return }
        overlayAdjustSession = nil
        onAdjustOverlay?(session.overlay, true)
    }
}
