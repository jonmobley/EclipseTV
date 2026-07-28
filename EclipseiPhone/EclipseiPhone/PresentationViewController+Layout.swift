//
//  PresentationViewController+Layout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Rotated / Scaled Layout

extension PresentationViewController {

    /// Sizes `content` to fill `container` with optional scale-up and portrait rotation.
    ///
    /// Shared by the AirPlay presentation surface and the phone web stage so both
    /// use the same logical viewport geometry.
    ///
    /// - Parameters:
    ///   - content: The view being laid out (camera preview or web view).
    ///   - container: The host panel (external display or phone stage).
    ///   - scale: Uniform scale applied after sizing. Camera uses `1`; web uses
    ///     `panelWidth / logicalWidth` so a mobile layout fills the panel.
    ///   - rotationDegrees: Override for phone (0) vs TV (`ExternalOutputSettings`).
    static func applyRotatedLayout(to content: UIView,
                                   in container: UIView,
                                   scale: CGFloat,
                                   rotationDegrees: Double? = nil) {
        let screenSize = container.bounds.size
        guard screenSize.width > 0, screenSize.height > 0, scale > 0 else { return }

        let contentSize: CGSize
        let degrees = rotationDegrees ?? ExternalOutputSettings.rotationDegrees
        if degrees != 0 {
            // TV Vertical: lay out in portrait space, then rotate into the landscape panel.
            contentSize = CGSize(width: screenSize.height, height: screenSize.width)
        } else {
            contentSize = screenSize
        }

        let logicalSize = CGSize(
            width: contentSize.width / scale,
            height: contentSize.height / scale
        )
        content.bounds = CGRect(origin: .zero, size: logicalSize)
        content.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)

        var transform = CGAffineTransform(scaleX: scale, y: scale)
        if degrees != 0 {
            transform = transform.rotated(by: CGFloat(degrees * .pi / 180))
        }
        content.transform = transform
    }

    /// Instance wrapper for call sites on the presentation controller.
    func applyRotatedLayout(to content: UIView, in container: UIView, scale: CGFloat) {
        Self.applyRotatedLayout(to: content, in: container, scale: scale)
    }

    /// Lays out a web view to the shared logical viewport, scaled to fill `container`.
    ///
    /// - Parameter rotationDegrees: Pass `0` on the phone (upright stage). TV uses
    ///   the ambient Vertical rotation from settings when `nil`.
    static func applyWebOutputLayout(to webView: UIView,
                                     in container: UIView,
                                     rotationDegrees: Double? = nil) {
        let screenSize = container.bounds.size
        guard screenSize.width > 0, screenSize.height > 0 else { return }

        let degrees = rotationDegrees ?? ExternalOutputSettings.rotationDegrees
        let contentSize: CGSize
        if degrees != 0 {
            contentSize = CGSize(width: screenSize.height, height: screenSize.width)
        } else {
            contentSize = screenSize
        }

        let logical = ExternalOutputSettings.webLogicalSize
        let scale = contentSize.width / logical.width
        applyRotatedLayout(
            to: webView,
            in: container,
            scale: scale,
            rotationDegrees: degrees
        )
    }
}
