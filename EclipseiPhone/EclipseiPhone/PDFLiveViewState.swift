//
//  PDFLiveViewState.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics

/// The reader's preset views (buttons in the hero and the full-screen reader).
enum PDFViewPreset: String, CaseIterable, Equatable {
    /// One whole page inside the frame.
    case fit
    /// One page filling the frame (the long side is cropped, scrolls).
    case fill
    /// Two pages side by side, both whole.
    case twoPages

    /// SF Symbol for the preset's button.
    var systemImage: String {
        switch self {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .twoPages: return "rectangle.split.2x1"
        }
    }

    var title: String {
        switch self {
        case .fit: return "Fit Page"
        case .fill: return "Fill Screen"
        case .twoPages: return "Two Pages"
        }
    }

    /// Whether the preset lays pages out two to a row.
    var isTwoUp: Bool { self == .twoPages }
}

/// How the live PDF is viewed, shared by everything that drives it (the hero and
/// the full-screen reader) and by the TV, which follows it.
///
/// Kept on `ExternalDisplayManager` so a reader opening, closing, or a hero being
/// rebuilt picks up exactly where the last one left off.
struct PDFLiveViewState: Equatable {
    var pageIndex = 0
    /// Scroll position as 0…1 fractions of the scrollable range, across and down.
    var progress = CGPoint.zero
    /// Zoom relative to PDFKit's own fit scale (`scaleFactorForSizeToFit`).
    var relativeScale: CGFloat = 1
    /// Two pages to a row.
    var isTwoUp = false
    /// The preset last chosen; `nil` once a pinch moves away from it.
    var preset: PDFViewPreset? = .fit
    /// Page by page: a swipe settles on the next page (or pair) instead of gliding.
    var snapsToPages = false
}

/// Pure geometry for presets and page-by-page scrolling (unit tested).
enum PDFViewMath {

    /// Zoom for `preset`, where `rowSizeAtScaleOne` is one row (a page, or a pair
    /// in two-page view) at zoom 1 and `container` is the audience frame.
    static func scale(
        for preset: PDFViewPreset,
        rowSizeAtScaleOne row: CGSize,
        container: CGSize
    ) -> CGFloat? {
        guard row.width > 0, row.height > 0,
              container.width > 0, container.height > 0 else { return nil }
        let across = container.width / row.width
        let down = container.height / row.height
        switch preset {
        case .fit, .twoPages: return min(across, down)
        case .fill: return max(across, down)
        }
    }

    /// Where a page-by-page swipe should settle, or `nil` to let it glide.
    ///
    /// - Parameters:
    ///   - rows: Each row's span down the document (content coordinates), in order.
    ///   - offset: Scroll offset (top of the visible area) when the finger lifts.
    ///   - projected: Where the glide would come to rest on its own.
    ///   - viewport: Visible height.
    ///   - range: Allowed offsets.
    ///
    /// A row that fits on screen is one stop, centred, and a swipe moves one stop
    /// in its direction. A row taller than the screen (zoomed in) scrolls freely
    /// between its top and bottom; a glide that would leave it stops at its edge,
    /// and a swipe from that edge moves on to the next row.
    static func snapOffset(
        rows: [ClosedRange<CGFloat>],
        offset: CGFloat,
        projected: CGFloat,
        viewport: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        guard !rows.isEmpty, viewport > 0, range.upperBound >= range.lowerBound else { return nil }
        func clamp(_ y: CGFloat) -> CGFloat { min(max(y, range.lowerBound), range.upperBound) }
        let tolerance: CGFloat = 2
        let swipe = projected - offset
        let direction = abs(swipe) < 24 ? 0 : (swipe > 0 ? 1 : -1)

        var stops: [CGFloat] = []
        for row in rows {
            let height = row.upperBound - row.lowerBound
            if height <= viewport + tolerance {
                stops.append(clamp(row.lowerBound + height / 2 - viewport / 2))
            } else {
                stops.append(clamp(row.lowerBound))
                stops.append(clamp(row.upperBound - viewport))
            }
        }
        stops.sort()
        let next = stops.first(where: { $0 > offset + tolerance })
        let previous = stops.last(where: { $0 < offset - tolerance })
        let nearest = stops.min(by: { abs($0 - offset) < abs($1 - offset) }) ?? clamp(offset)

        // Inside (or at the edge of) a zoomed-in row taller than the screen.
        for row in rows where row.upperBound - row.lowerBound > viewport + tolerance {
            let top = clamp(row.lowerBound)
            let bottom = clamp(row.upperBound - viewport)
            guard offset >= top - tolerance, offset <= bottom + tolerance else { continue }
            if projected >= top, projected <= bottom { return nil }
            if projected > bottom {
                return offset < bottom - tolerance ? bottom : (next ?? bottom)
            }
            return offset > top + tolerance ? top : (previous ?? top)
        }

        switch direction {
        case 1: return next ?? nearest
        case -1: return previous ?? nearest
        default: return nearest
        }
    }

    /// Where UIKit's normal deceleration would bring a glide to rest.
    static func projectedOffset(_ offset: CGFloat, velocity: CGFloat) -> CGFloat {
        // UIScrollView.DecelerationRate.normal (0.998 per ms).
        let rate: CGFloat = 0.998
        return offset + velocity / 1000 * rate / (1 - rate)
    }
}
