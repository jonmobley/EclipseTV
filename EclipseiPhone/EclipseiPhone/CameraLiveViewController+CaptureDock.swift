//
//  CameraLiveViewController+CaptureDock.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Capture Dock Edge

/// Screen edge that carries Frame · photo · record · Flip.
///
/// The dock lives on the phone's physical bottom edge in every hold. Turning the
/// phone counterclockwise puts that edge on the right of the rotated interface;
/// turning it clockwise puts it on the left. Following the turn keeps the record
/// button under the same thumb, the way the system Camera app does.
enum CaptureDockEdge: Equatable {
    /// Row under the panel (portrait hold).
    case bottom
    /// Column on the left of the rotated interface (phone turned clockwise).
    case left
    /// Column on the right of the rotated interface (phone turned counterclockwise).
    case right
}

// MARK: - Dock Geometry

extension CameraLiveViewController {

    /// Bottom shutter dock when the camera UI is taller than it is wide.
    var isPhoneCameraPortraitLayout: Bool {
        stageView.bounds.height >= stageView.bounds.width
    }

    /// Edge the dock sits on for the current hold.
    var captureDockEdge: CaptureDockEdge {
        Self.captureDockEdge(
            isPortraitLayout: isPhoneCameraPortraitLayout,
            interfaceOrientation: view.phoneInterfaceOrientation
        )
    }

    /// Picks the dock edge that is the phone's physical bottom in this hold.
    ///
    /// `landscapeRight` is the home indicator on the right — the phone turned
    /// counterclockwise, so the portrait bottom edge is on the right. `landscapeLeft`
    /// is the mirror. Anything else in a landscape layout (iPad multitasking, an
    /// unknown scene) keeps the trailing column.
    static func captureDockEdge(
        isPortraitLayout: Bool,
        interfaceOrientation: UIInterfaceOrientation
    ) -> CaptureDockEdge {
        guard !isPortraitLayout else { return .bottom }
        return interfaceOrientation == .landscapeLeft ? .left : .right
    }

    /// Safe-area pad on the dock's own edge.
    func captureDockSafePad(for edge: CaptureDockEdge) -> CGFloat {
        switch edge {
        case .bottom: return view.safeAreaInsets.bottom
        case .left: return view.safeAreaInsets.left
        case .right: return view.safeAreaInsets.right
        }
    }

    /// Outside-panel strip for Frame · photo · record · Flip
    /// (gap + record button + safe-area pad).
    static func captureDockSpan(safeEdge: CGFloat) -> CGFloat {
        chromeGap + shutterSize + max(8, safeEdge)
    }

    /// Largest Display Mode panel in the stage, with the shutter strip reserved outside.
    ///
    /// Dock follows how the phone is held, not Show format: bottom in portrait,
    /// left or right in landscape depending on which way it turned. Aspect stays
    /// the Show's 16:9 / 9:16 — a Landscape Show on a portrait phone is a 16:9
    /// crop, matching the home Camera tile.
    static func phoneCameraPanelRect(
        in bounds: CGRect,
        aspect: CGFloat,
        dockEdge: CaptureDockEdge,
        dockSpan: CGFloat
    ) -> CGRect {
        let available: CGRect
        switch dockEdge {
        case .bottom:
            available = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: max(0, bounds.height - dockSpan)
            )
        case .right:
            available = CGRect(
                x: 0,
                y: 0,
                width: max(0, bounds.width - dockSpan),
                height: bounds.height
            )
        case .left:
            available = CGRect(
                x: dockSpan,
                y: 0,
                width: max(0, bounds.width - dockSpan),
                height: bounds.height
            )
        }
        guard available.width > 1, available.height > 1 else { return .zero }

        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }

        let x = available.midX - width / 2
        let y = available.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
