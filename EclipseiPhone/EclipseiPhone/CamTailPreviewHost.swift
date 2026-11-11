//
//  CamTailPreviewHost.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CamTailKit
import SwiftUI
import UIKit

/// Hosts CamTailKit's `CamTailLivePreview` (live picture, or a plain message about the
/// camera's state) as a UIKit view for the PTZ tile and the hero.
///
/// Only placement lives here; what the preview says comes from CamTailKit.
enum CamTailPreviewHost {

    /// A view filling its container with the PTZ preview.
    /// - Parameter compact: one-line status, for grid tiles.
    @MainActor
    static func makeView(compact: Bool) -> UIView {
        let host = UIHostingController(
            rootView: CamTailLivePreview(fillsView: true, compact: compact)
        )
        let view = host.view!
        view.backgroundColor = .black
        // Taps belong to the tile / hero underneath.
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        // Keep the controller alive while its view is placed; `remove(_:)` lets it go.
        objc_setAssociatedObject(view, &hostKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return view
    }

    /// Takes a preview off screen and frees its controller (the view and the
    /// controller hold each other until then).
    @MainActor
    static func remove(_ view: UIView?) {
        guard let view else { return }
        view.removeFromSuperview()
        objc_setAssociatedObject(view, &hostKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    nonisolated(unsafe) private static var hostKey: UInt8 = 0
}
