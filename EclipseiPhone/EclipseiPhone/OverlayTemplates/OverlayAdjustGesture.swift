//
//  OverlayAdjustGesture.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Pure math for moving and resizing a live overlay with a finger
//               drag or a pinch on the phone's live preview (the iPhone/iPad
//               counterpart of the Mac's EditableCardOverlay drag / resize).
//               Works on the overlay's on-screen frame, so the same rules serve
//               template cards (center + size multiplier) and photo / video
//               overlays (center + width fraction).
//  Thread Safety: Value types - no shared mutable state.
//

import CoreGraphics

// MARK: - OverlayAdjustSession

/// One drag / pinch on a live overlay, from the first finger down to the last up.
///
/// Usage: start it from the overlay as drawn (`frame` in the layer's points),
/// feed it finger movement and pinch scale, then read `overlay` for what to draw
/// and, on lift, what to save.
struct OverlayAdjustSession {

    // MARK: - Constants

    /// How close (points) the center must come to a centerline to snap onto it.
    static let snapDistance: CGFloat = 8

    // MARK: - Properties

    /// The overlay as it was when the fingers came down.
    let original: RenderedOverlay
    /// Program frame the overlay is placed in (layer points).
    let contentFrame: CGRect
    /// On-screen size at a size factor of 1 (card scale 1, or full frame width).
    let unitSize: CGSize
    /// Size factor when the fingers came down.
    let startFactor: CGFloat
    /// Center as drawn when the fingers came down (layer points).
    let startCenter: CGPoint
    /// Unclamped center the fingers are carrying (layer points).
    private(set) var rawCenter: CGPoint
    /// Size factor the fingers are asking for (clamped to the overlay's range).
    private(set) var factor: CGFloat
    /// Centerlines the center currently sits on.
    private(set) var snap = OverlayAdjustSnap()

    // MARK: - Initialization

    /// Starts a session for `overlay` drawn at `frame` inside `contentFrame`.
    ///
    /// Returns nil when either rectangle is empty (nothing measured yet).
    init?(overlay: RenderedOverlay, frame: CGRect, contentFrame: CGRect) {
        guard frame.width > 0, frame.height > 0,
              contentFrame.width > 0, contentFrame.height > 0 else { return nil }
        original = overlay
        self.contentFrame = contentFrame
        startCenter = CGPoint(x: frame.midX, y: frame.midY)
        rawCenter = startCenter
        switch overlay {
        case .card(let card):
            let scale = card.config.placement?.clamped().scale ?? 1
            startFactor = scale
            unitSize = CGSize(width: frame.width / scale, height: frame.height / scale)
        case .media(let entry):
            let scale = CGFloat(entry.clamped().scale)
            startFactor = scale
            unitSize = CGSize(width: frame.width / scale, height: frame.height / scale)
        }
        factor = startFactor
    }

    // MARK: - Gesture Input

    /// Moves the overlay by `delta` points.
    mutating func move(by delta: CGPoint) {
        rawCenter.x += delta.x
        rawCenter.y += delta.y
    }

    /// Resizes by `ratio` (a pinch's scale since the last call).
    mutating func scale(by ratio: CGFloat) {
        guard ratio.isFinite, ratio > 0 else { return }
        factor = Self.clampFactor(factor * ratio, for: original)
    }

    // MARK: - Output

    /// On-screen size at the current factor.
    var size: CGSize {
        CGSize(width: unitSize.width * factor, height: unitSize.height * factor)
    }

    /// Center to draw at: snapped onto the frame's centerlines when close.
    ///
    /// A card keeps its whole body inside the frame (as on the Mac). A photo or
    /// video overlay only keeps its center inside, like `MediaOverlayEntry.clamped()`,
    /// so a logo may hang off an edge, also as on the Mac.
    var center: CGPoint {
        let snapped = OverlayAdjustSnap.apply(to: rawCenter, in: contentFrame,
                                              distance: Self.snapDistance).point
        switch original {
        case .card:
            return OverlayCardLayout.clampedCenter(snapped, cardSize: size, in: contentFrame)
        case .media:
            return CGPoint(
                x: min(contentFrame.maxX, max(contentFrame.minX, snapped.x)),
                y: min(contentFrame.maxY, max(contentFrame.minY, snapped.y))
            )
        }
    }

    /// Recomputes `snap` and reports whether the center just landed on a line
    /// it was not on before (time for a haptic tick).
    mutating func refreshSnap() -> Bool {
        let next = OverlayAdjustSnap.apply(to: rawCenter, in: contentFrame,
                                           distance: Self.snapDistance).snap
        defer { snap = next }
        return (next.vertical && !snap.vertical) || (next.horizontal && !snap.horizontal)
    }

    /// Whether anything moved or resized since the fingers came down.
    var hasChanged: Bool {
        overlay != original
    }

    /// The overlay with its new position and size.
    var overlay: RenderedOverlay {
        let unit = OverlayCardLayout.normalized(center, in: contentFrame)
        switch original {
        case .card(var card):
            if !hasMovedOrResized { return original }
            card.config.placement = OverlayCardPlacement(
                centerX: unit.x, centerY: unit.y, scale: factor
            ).clamped()
            return .card(card)
        case .media(var entry):
            if !hasMovedOrResized { return original }
            entry.centerX = Double(unit.x)
            entry.centerY = Double(unit.y)
            entry.scale = Double(factor)
            return .media(entry.clamped())
        }
    }

    // MARK: - Private

    /// A docked card that was touched but not moved keeps its corner dock.
    ///
    /// Reads the fingers (`rawCenter`), not the drawn `center`: an overlay that
    /// already sits near a centerline would otherwise count as moved by the snap
    /// alone, and a touch that never moved would save it as a free placement.
    private var hasMovedOrResized: Bool {
        abs(rawCenter.x - startCenter.x) > 0.5 || abs(rawCenter.y - startCenter.y) > 0.5
            || abs(factor - startFactor) > 0.001
    }

    private static func clampFactor(_ value: CGFloat, for overlay: RenderedOverlay) -> CGFloat {
        switch overlay {
        case .card:
            return min(OverlayCardPlacement.maxScale, max(OverlayCardPlacement.minScale, value))
        case .media:
            let range = MediaOverlayEntry.scaleRange
            return min(CGFloat(range.upperBound), max(CGFloat(range.lowerBound), value))
        }
    }
}

// MARK: - OverlayAdjustSnap

/// Which of the program frame's centerlines an overlay's center sits on.
struct OverlayAdjustSnap: Equatable {
    /// On the vertical centerline (centered left to right).
    var vertical = false
    /// On the horizontal centerline (centered top to bottom).
    var horizontal = false

    /// Pulls `point` onto a centerline of `frame` when within `distance` points.
    static func apply(to point: CGPoint, in frame: CGRect,
                      distance: CGFloat) -> (point: CGPoint, snap: OverlayAdjustSnap) {
        var result = point
        var snap = OverlayAdjustSnap()
        if abs(point.x - frame.midX) <= distance {
            result.x = frame.midX
            snap.vertical = true
        }
        if abs(point.y - frame.midY) <= distance {
            result.y = frame.midY
            snap.horizontal = true
        }
        return (result, snap)
    }
}
