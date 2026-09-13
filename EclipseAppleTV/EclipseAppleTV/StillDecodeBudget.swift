//
//  StillDecodeBudget.swift
//  EclipseAppleTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Kept identical to EclipseiPhone/EclipseiPhone/StillDecodeBudget.swift so both
//  outputs decode a still to the same size for the same framing.
//

import CoreGraphics
import Foundation

/// Longest-edge decode ceiling for a fullscreen still, sized from the pixels that
/// will actually be on screen rather than from the panel's longest edge.
///
/// Capping the decode at the panel's longest edge is only right for Fit. Fill covers
/// the panel with `max(panelW / imageW, panelH / imageH)`, so any still whose aspect
/// differs from the panel has to be scaled *up* from that bitmap and looks soft: a
/// portrait photo on a 16:9 output is magnified 1.33×, a 4:1 panorama 2.25×. A custom
/// crop is worse still — cropping half the width leaves half the pixels the panel
/// needs. This computes the ceiling so the visible region lands at panel density.
enum StillDecodeBudget {

    /// How the decoded bitmap is placed in the panel.
    enum Placement: Equatable {
        /// Letterboxed; the whole image is visible.
        case fit
        /// Cropped to cover the panel.
        case fill
        /// Cropped to a unit-space rect (origin top-left), then letterboxed.
        case crop(CGRect)

        /// Stable string for cache keys.
        var cacheKey: String {
            switch self {
            case .fit: return "fit"
            case .fill: return "fill"
            case .crop(let rect):
                return String(
                    format: "crop_%.4f_%.4f_%.4f_%.4f",
                    rect.origin.x, rect.origin.y, rect.width, rect.height
                )
            }
        }
    }

    /// Bound on the decode relative to the panel's longest edge.
    ///
    /// Fill of an extreme aspect (a 1:10 banner on 16:9) would otherwise ask for a
    /// bitmap many screens tall for a strip that is mostly cropped away. Such a still
    /// is still decoded larger than before; it just stops short of tens of megapixels.
    static let panelEdgeMultiplier: CGFloat = 2

    /// Longest-edge ceiling in pixels for ImageIO's `kCGImageSourceThumbnailMaxPixelSize`.
    ///
    /// Never exceeds the source's own longest edge (no upsampling) and never exceeds
    /// `panelEdgeMultiplier` × the panel's longest edge. Degenerate inputs fall back
    /// to the panel's longest edge, which is the pre-existing behaviour.
    ///
    /// - Parameters:
    ///   - sourcePixelSize: Upright pixel size of the encoded image.
    ///   - panelPixelSize: Pixel size of the surface the still is shown in.
    ///   - placement: How the still is framed in that surface.
    static func maxPixelEdge(
        sourcePixelSize source: CGSize,
        panelPixelSize panel: CGSize,
        placement: Placement
    ) -> Int {
        let panelLongest = max(panel.width, panel.height)
        let fallback = max(1, Int(panelLongest.rounded(.up)))
        guard source.width > 0, source.height > 0,
              panel.width > 0, panel.height > 0,
              source.width.isFinite, source.height.isFinite,
              panel.width.isFinite, panel.height.isFinite else {
            return fallback
        }

        let visible: CGSize
        switch placement {
        case .fit, .fill:
            visible = source
        case .crop(let unit):
            visible = CGSize(
                width: unit.width * source.width,
                height: unit.height * source.height
            )
        }
        guard visible.width > 0, visible.height > 0 else { return fallback }

        // Fill scales by the larger of panelW/visibleW and panelH/visibleH, Fit and a
        // crop by the smaller. Pick the axis by cross-multiplying and divide once at
        // the end so integer-valued results stay exact instead of ceiling to N+1.
        let widthBound = panel.width * visible.height > panel.height * visible.width
        let useWidth = placement == .fill ? widthBound : !widthBound
        let sourceLongest = max(source.width, source.height)
        let needed = useWidth
            ? (sourceLongest * panel.width / visible.width).rounded(.up)
            : (sourceLongest * panel.height / visible.height).rounded(.up)
        let ceiling = min(sourceLongest, panelLongest * panelEdgeMultiplier)
        return max(1, Int(min(needed, ceiling).rounded(.up)))
    }
}
