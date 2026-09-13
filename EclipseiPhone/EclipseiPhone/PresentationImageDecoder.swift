//
//  PresentationImageDecoder.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import ImageIO
import UIKit

/// Decodes fullscreen presentation stills off the main thread at display size.
///
/// `UIImage(contentsOfFile:)` is lazy: a 12 MP photo decodes on the main thread at
/// first paint and hitchs the AirPlay encode. ImageIO downsamples to what the panel
/// will show and `preparingForDisplay()` forces the decode here.
///
/// The ceiling comes from `StillDecodeBudget`, not the screen's longest edge: Fill
/// and custom crops need more of the source than Fit does, and a still decoded only
/// to the screen edge gets magnified by `.scaleAspectFill` and looks soft.
enum PresentationImageDecoder {

    /// Default longest-edge ceiling when no external screen bounds are known (1080p).
    static let fallbackMaxPixelEdge = 1920

    /// Default panel when no external screen bounds are known (1080p landscape).
    static let fallbackPanelPixelSize = CGSize(width: 1920, height: 1080)

    /// Longest edge of `screen`'s native bounds, or `fallbackMaxPixelEdge`.
    static func maxPixelEdge(for screen: UIScreen?) -> Int {
        guard let screen else { return fallbackMaxPixelEdge }
        let bounds = screen.nativeBounds
        let edge = max(bounds.width, bounds.height)
        guard edge.isFinite, edge > 0 else { return fallbackMaxPixelEdge }
        return Int(edge.rounded(.up))
    }

    /// Pixel size of the media panel on `screen`.
    ///
    /// External framebuffers are landscape, so the long native edge is the width. In
    /// Vertical Display Mode the media surface is laid out tall and rotated into the
    /// framebuffer, so the two swap — the still is framed against a 9:16 panel.
    ///
    /// - Parameters:
    ///   - screen: External screen, or nil for `fallbackPanelPixelSize`.
    ///   - rotationDegrees: Display Mode rotation; 90° / 270° swap the edges.
    static func panelPixelSize(
        for screen: UIScreen?,
        rotationDegrees: Double = ExternalOutputSettings.rotationDegrees
    ) -> CGSize {
        var panel = fallbackPanelPixelSize
        if let screen {
            let bounds = screen.nativeBounds
            let long = max(bounds.width, bounds.height)
            let short = min(bounds.width, bounds.height)
            if long.isFinite, short.isFinite, short > 0 {
                panel = CGSize(width: long, height: short)
            }
        }
        if rotationSwapsPanelEdges(rotationDegrees) {
            return CGSize(width: panel.height, height: panel.width)
        }
        return panel
    }

    /// 90° and 270° swap the panel's edges; 0° and 180° keep them. Mirrors
    /// `PresentationViewController.rotationSwapsDimensions`, which is main-actor bound.
    private static func rotationSwapsPanelEdges(_ degrees: Double) -> Bool {
        let normalized = abs(degrees).truncatingRemainder(dividingBy: 180)
        return abs(normalized - 90) < 0.5
    }

    /// Placement for a library still: a custom crop wins over Fit / Fill.
    static func placement(
        fill: Bool,
        framing: MediaFraming?
    ) -> StillDecodeBudget.Placement {
        if let framing, framing.width > 0, framing.height > 0 {
            return .crop(CGRect(
                x: framing.x, y: framing.y,
                width: framing.width, height: framing.height
            ))
        }
        return fill ? .fill : .fit
    }

    /// Decodes `fileURL` downsampled so its longest edge is at most `maxPixelEdge`.
    ///
    /// Must be called off the main thread. Returns a display-ready bitmap, or nil
    /// when the file is missing or not a readable image.
    ///
    /// - Parameters:
    ///   - fileURL: Local image file.
    ///   - maxPixelEdge: Longest-edge ceiling in pixels (external screen native size).
    nonisolated static func decode(
        fileURL: URL,
        maxPixelEdge: Int
    ) -> UIImage? {
        guard let image = ThumbnailDecoder.decode(
            fileURL: fileURL,
            maxPixelEdge: max(1, maxPixelEdge)
        ) else { return nil }
        return image.preparingForDisplay() ?? image
    }

    /// Decodes `fileURL` sized so the region `placement` shows fills `panelPixelSize`
    /// at native density.
    ///
    /// Must be called off the main thread. Returns a display-ready bitmap, or nil
    /// when the file is missing or not a readable image. The caller still applies
    /// the crop for `.crop` — this only guarantees enough pixels survive it.
    ///
    /// - Parameters:
    ///   - fileURL: Local image file.
    ///   - panelPixelSize: Pixel size of the surface the still is shown in.
    ///   - placement: Fit, Fill, or a unit-space custom crop.
    nonisolated static func decode(
        fileURL: URL,
        panelPixelSize: CGSize,
        placement: StillDecodeBudget.Placement
    ) -> UIImage? {
        guard let image = ThumbnailDecoder.decode(fileURL: fileURL, maxPixelEdge: { source in
            StillDecodeBudget.maxPixelEdge(
                sourcePixelSize: source,
                panelPixelSize: panelPixelSize,
                placement: placement
            )
        }) else { return nil }
        return image.preparingForDisplay() ?? image
    }
}
