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
    /// - Parameters:
    ///   - content: The view being laid out (camera preview or web view).
    ///   - container: The fullscreen host on the external display.
    ///   - scale: Uniform scale applied after sizing. Camera uses `1`; web uses
    ///     `contentWidth / logicalWidth` so a mobile layout fills the TV.
    func applyRotatedLayout(to content: UIView, in container: UIView, scale: CGFloat) {
        let screenSize = container.bounds.size
        guard screenSize.width > 0, screenSize.height > 0, scale > 0 else { return }

        let contentSize: CGSize
        if ExternalOutputSettings.orientation == .portrait {
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

        let degrees = ExternalOutputSettings.rotationDegrees
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        if degrees != 0 {
            transform = transform.rotated(by: CGFloat(degrees * .pi / 180))
        }
        content.transform = transform
    }
}
