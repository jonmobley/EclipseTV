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
    ///     `panelWidth / logicalWidth` so a desktop layout fills the panel.
    ///   - rotationDegrees: Override for phone (0) vs TV (`ExternalOutputSettings`).
    static func applyRotatedLayout(to content: UIView,
                                   in container: UIView,
                                   scale: CGFloat,
                                   rotationDegrees: Double? = nil) {
        let screenSize = container.bounds.size
        guard screenSize.width > 0, screenSize.height > 0, scale > 0 else { return }

        let degrees = rotationDegrees ?? ExternalOutputSettings.rotationDegrees
        let contentSize = rotatedContentSize(
            for: screenSize,
            rotationDegrees: degrees
        )

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

    /// 90° and 270° swap width/height so the rotated view still fills the panel.
    /// 180° must not swap — rotating a 16:9 view 90° without a swap clips to a square.
    static func rotationSwapsDimensions(_ degrees: Double) -> Bool {
        let normalized = abs(degrees).truncatingRemainder(dividingBy: 180)
        return abs(normalized - 90) < 0.5
    }

    /// Un-rotated content size that fills `container` after `rotationDegrees`.
    static func rotatedContentSize(
        for container: CGSize,
        rotationDegrees: Double
    ) -> CGSize {
        if rotationSwapsDimensions(rotationDegrees) {
            return CGSize(width: container.height, height: container.width)
        }
        return container
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
        let contentSize = rotatedContentSize(
            for: screenSize,
            rotationDegrees: degrees
        )

        let logical = ExternalOutputSettings.webLogicalSize
        let scale = contentSize.width / logical.width
        applyRotatedLayout(
            to: webView,
            in: container,
            scale: scale,
            rotationDegrees: degrees
        )
    }

    /// Lays out QuestPoll `/present`: host bounds are the CSS viewport.
    ///
    /// The page owns a fixed 1920×1080 stage and scales once into that viewport.
    /// Using the desktop `webLogicalSize` path here would double-scale and shrink
    /// the composition. Generic website bookmarks still use `applyWebOutputLayout`.
    ///
    /// - Parameter rotationDegrees: Pass `0` on the phone hero; TV may rotate.
    static func applyPresentEmbedLayout(
        to webView: UIView,
        in container: UIView,
        rotationDegrees: Double? = nil
    ) {
        applyRotatedLayout(
            to: webView,
            in: container,
            scale: 1,
            rotationDegrees: rotationDegrees
        )
    }

    /// How a web surface fills its host panel.
    enum WebLayoutMode: Equatable {
        /// Desktop logical viewport scaled up to the panel (generic bookmarks).
        case desktopLogical
        /// Host bounds are the CSS viewport (QuestPoll `/present`, video embeds).
        case nativeViewport
    }

    /// Layout mode for a live page URL (or video shell with no navigable URL).
    static func webLayoutMode(pageURL: URL?, isWebVideoShell: Bool = false) -> WebLayoutMode {
        if isWebVideoShell { return .nativeViewport }
        if let pageURL, QuestPollConfig.isPresentURL(pageURL) {
            return .nativeViewport
        }
        return .desktopLogical
    }

    /// Picks present-embed vs desktop logical layout from `pageURL`.
    static func applyWebLayout(
        to webView: UIView,
        in container: UIView,
        pageURL: URL?,
        rotationDegrees: Double? = nil,
        isWebVideoShell: Bool = false
    ) {
        switch webLayoutMode(pageURL: pageURL, isWebVideoShell: isWebVideoShell) {
        case .nativeViewport:
            applyPresentEmbedLayout(
                to: webView,
                in: container,
                rotationDegrees: rotationDegrees
            )
        case .desktopLogical:
            applyWebOutputLayout(
                to: webView,
                in: container,
                rotationDegrees: rotationDegrees
            )
        }
    }
}
