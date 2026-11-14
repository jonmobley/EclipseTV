//
//  PDFZoomSnap.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics

/// Zoom levels a pinch in the PDF reader catches on: the page exactly as wide
/// as the audience frame, and the page exactly as tall as it.
///
/// Pure math so it can be tested; `PDFRemoteViewController` measures the page
/// and applies the result.
enum PDFZoomSnap {

    /// How close (as a fraction of the target) a pinch must come before the
    /// zoom holds on a snap size. Pinching past it lets go.
    static let holdBand: CGFloat = 0.04

    /// Two snap targets closer than this (fraction) count as one.
    static let mergeBand: CGFloat = 0.01

    /// Scale factors at which the page fills the container's width and height.
    ///
    /// - Parameters:
    ///   - pageSizeAtScaleOne: The page's drawn size at scale factor 1, in points.
    ///   - container: The frame the page is judged against (the audience frame).
    ///   - range: Allowed scale factors; targets outside are dropped.
    /// - Returns: Distinct targets, smallest first.
    static func targets(
        pageSizeAtScaleOne page: CGSize,
        container: CGSize,
        range: ClosedRange<CGFloat>
    ) -> [CGFloat] {
        guard page.width > 0, page.height > 0,
              container.width > 0, container.height > 0 else { return [] }
        let candidates = [container.width / page.width, container.height / page.height]
            .filter { range.contains($0) }
            .sorted()
        var result: [CGFloat] = []
        for scale in candidates {
            if let last = result.last, abs(scale / last - 1) < mergeBand { continue }
            result.append(scale)
        }
        return result
    }

    /// The target `scale` should hold on, if it is within `band` of one.
    static func target(
        for scale: CGFloat,
        in targets: [CGFloat],
        band: CGFloat = holdBand
    ) -> CGFloat? {
        guard scale > 0 else { return nil }
        return targets
            .filter { abs(scale / $0 - 1) <= band }
            .min { abs(scale / $0 - 1) < abs(scale / $1 - 1) }
    }
}
