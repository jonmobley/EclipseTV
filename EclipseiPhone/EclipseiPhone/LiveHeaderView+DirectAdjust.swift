//
//  LiveHeaderView+DirectAdjust.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Direct Adjust (pinch / drag on the hero)

/// What a pinch or drag on the expanded hero changes.
enum DirectAdjustTarget: Equatable {
    /// The live countdown's clock size and position.
    case countdown(UUID)
    /// The live still's zoom and position. `isAdjusted` means it already has a
    /// custom position, so a one-finger drag pans instead of browsing.
    case still(id: String, mode: MediaFitMode, isAdjusted: Bool)
}

/// Progress of one pinch / drag, from the first finger down to the last one up.
struct DirectAdjustSession {
    var countdownLayout: CountdownClockLayout = .default
    /// Region of the still on screen, in the still's point space.
    var stillRect: CGRect = .zero
    var stillSize: CGSize = .zero
    /// Pinch centre last frame, so moving both fingers also moves the content.
    var lastPinchLocation: CGPoint?
}

extension LiveHeaderView {

    /// Installs the pinch and the one-finger drag. Browse swipes wait for the drag
    /// to fail, which it does at once unless there is something to drag.
    func installDirectAdjustGestures() {
        let pinch = UIPinchGestureRecognizer(
            target: self, action: #selector(handleDirectAdjustPinch(_:))
        )
        pinch.delegate = self
        addGestureRecognizer(pinch)
        directAdjustPinch = pinch

        let pan = UIPanGestureRecognizer(
            target: self, action: #selector(handleDirectAdjustPan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        directAdjustPan = pan

        for swipe in browseSwipeRecognizers {
            swipe.require(toFail: pan)
        }
    }

    /// Whether `gesture` may start a direct adjustment right now.
    func directAdjustShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard !isCompactPresentation, let target = directAdjustTarget else { return false }
        let isPinch = gesture === directAdjustPinch
        switch target {
        case .countdown:
            guard !countdownClockLabel.isHidden else { return false }
            if isPinch { return true }
            let point = gesture.location(in: self)
            return countdownClockLabel.frame.insetBy(dx: -28, dy: -28).contains(point)
        case .still(let id, _, let isAdjusted):
            guard directAdjustStill?.id == id, !imageView.isHidden else { return false }
            return isPinch || isAdjusted || directAdjustSession != nil
        }
    }

    // MARK: - Private

    @objc private func handleDirectAdjustPinch(_ gesture: UIPinchGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            beginDirectAdjustSessionIfNeeded()
            directAdjustSession?.lastPinchLocation = location
            gesture.scale = 1
        case .changed:
            guard var session = directAdjustSession else { return }
            let delta = session.lastPinchLocation.map {
                CGPoint(x: location.x - $0.x, y: location.y - $0.y)
            } ?? .zero
            session.lastPinchLocation = location
            let scale = gesture.scale
            gesture.scale = 1
            switch directAdjustTarget {
            case .countdown:
                let text = countdownClockLabel.text ?? "0:00"
                session.countdownLayout = session.countdownLayout
                    .scaling(
                        to: session.countdownLayout.scale * Double(scale),
                        text: text,
                        in: bounds
                    )
                    .translating(by: delta, text: text, in: bounds)
            case .still:
                let anchor = unitPoint(location, showing: session.stillRect)
                let zoomed = StillFramingGesture.zoomed(
                    session.stillRect, by: scale, anchor: anchor, imageSize: session.stillSize
                )
                session.stillRect = StillFramingGesture.panned(
                    zoomed, by: delta, viewSize: bounds.size, imageSize: session.stillSize
                )
            case nil:
                return
            }
            directAdjustSession = session
            renderDirectAdjustSession()
        case .ended, .cancelled, .failed:
            directAdjustSession?.lastPinchLocation = nil
            finishDirectAdjustIfIdle()
        default:
            break
        }
    }

    @objc private func handleDirectAdjustPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginDirectAdjustSessionIfNeeded()
            gesture.setTranslation(.zero, in: self)
        case .changed:
            guard var session = directAdjustSession else { return }
            let delta = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            switch directAdjustTarget {
            case .countdown:
                session.countdownLayout = session.countdownLayout.translating(
                    by: delta, text: countdownClockLabel.text ?? "0:00", in: bounds
                )
            case .still:
                session.stillRect = StillFramingGesture.panned(
                    session.stillRect,
                    by: delta,
                    viewSize: bounds.size,
                    imageSize: session.stillSize
                )
            case nil:
                return
            }
            directAdjustSession = session
            renderDirectAdjustSession()
        case .ended, .cancelled, .failed:
            finishDirectAdjustIfIdle()
        default:
            break
        }
    }

    private func beginDirectAdjustSessionIfNeeded() {
        guard directAdjustSession == nil, let target = directAdjustTarget else { return }
        var session = DirectAdjustSession()
        switch target {
        case .countdown(let id):
            session.countdownLayout = CountdownClockLayoutPreview.resolved(for: id)
        case .still(let id, let mode, _):
            guard let image = directAdjustStill?.image else { return }
            let size = MediaAspect.normalized(image).size
            session.stillSize = size
            session.stillRect = StillFramingGesture.startRect(
                imageSize: size,
                framing: MediaFramingStore.framing(forId: id),
                mode: mode,
                aspect: MediaAspect.activeTarget
            )
        }
        directAdjustSession = session
    }

    /// Draws the in-flight adjustment on the hero (and, for the clock, on output).
    private func renderDirectAdjustSession() {
        guard let session = directAdjustSession else { return }
        switch directAdjustTarget {
        case .countdown(let id):
            onAdjustCountdown?(id, session.countdownLayout, false)
        case .still:
            guard let image = directAdjustStill?.image,
                  let framed = MediaAspect.framed(image, to: session.stillRect) else { return }
            imageView.contentMode = .scaleAspectFit
            imageView.image = framed
        case nil:
            break
        }
    }

    /// Saves once no adjusting finger is left on the hero.
    private func finishDirectAdjustIfIdle() {
        let active: [UIGestureRecognizer.State] = [.began, .changed]
        if let pinch = directAdjustPinch, active.contains(pinch.state) { return }
        if let pan = directAdjustPan, active.contains(pan.state) { return }
        guard let session = directAdjustSession else { return }
        directAdjustSession = nil
        switch directAdjustTarget {
        case .countdown(let id):
            onAdjustCountdown?(id, session.countdownLayout, true)
        case .still(let id, let mode, _):
            forgetPresentedContent()
            let outcome = StillFramingGesture.outcome(
                for: session.stillRect, imageSize: session.stillSize, currentMode: mode
            )
            onAdjustStill?(id, outcome)
        case nil:
            break
        }
    }

    /// Where `point` falls in the still region shown aspect-fit, as 0…1 per axis.
    private func unitPoint(_ point: CGPoint, showing rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0,
              bounds.width > 0, bounds.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let scale = min(bounds.width / rect.width, bounds.height / rect.height)
        let shown = CGSize(width: rect.width * scale, height: rect.height * scale)
        let origin = CGPoint(
            x: (bounds.width - shown.width) / 2,
            y: (bounds.height - shown.height) / 2
        )
        return CGPoint(
            x: min(max((point.x - origin.x) / shown.width, 0), 1),
            y: min(max((point.y - origin.y) / shown.height, 0), 1)
        )
    }
}
