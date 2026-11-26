//
//  OverlayCardPlate.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: The one backing plate every card layout sits on: plate fill,
//               accent spine on the leading edge, hairline, and the shared
//               drop shadow. Replaces the per-layout `cardBackground` copies so
//               all templates share one legibility rule.
//  Thread Safety: Main thread only - SwiftUI view modifier.
//

import SwiftUI

// MARK: - OverlayCardPlate

/// Backing plate for a card overlay at the 1080p reference scale.
///
/// The plate is the family's legibility rule: a near-solid fill, a soft shadow
/// that lifts it off busy video, a hairline that keeps light plates visible
/// over light footage, and the accent spine that marks every card as one of
/// the set. Spine and hairline follow the plate's corner radius.
struct OverlayCardPlate: ViewModifier {

    // MARK: - Properties

    let style: OverlayCardStyle
    let scale: CGFloat
    /// Whether the accent spine runs down the leading edge.
    var showsSpine: Bool = true

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(alignment: .leading) {
                if showsSpine {
                    spine
                }
            }
            .clipShape(shape)
            .overlay(hairline)
            .shadow(
                color: .black.opacity(OverlayCardTheme.Shadow.opacity),
                radius: OverlayCardTheme.Shadow.radius * scale,
                x: 0,
                y: OverlayCardTheme.Shadow.offsetY * scale
            )
    }

    // MARK: - Pieces

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: style.cornerRadius * scale,
            style: .continuous
        )
    }

    private var fill: some View {
        shape.fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
    }

    private var spine: some View {
        Rectangle()
            .fill(style.resolvedAccent.color)
            .frame(width: OverlayCardTheme.Space.spine * scale)
    }

    /// Light plates get a dark hairline so their edge survives bright footage;
    /// dark plates get a faint light one so they do not vanish on black.
    private var hairline: some View {
        shape.strokeBorder(
            style.isLightPlate
                ? Color.black.opacity(0.12)
                : Color.white.opacity(0.08),
            lineWidth: max(1, scale)
        )
    }
}

// MARK: - View Extension

extension View {

    /// Places this content on the shared card plate.
    ///
    /// - Parameters:
    ///   - style: The card's resolved style (plate color, radius, accent).
    ///   - scale: Multiplier applied to every metric (1.0 == 1080p).
    ///   - showsSpine: Whether to draw the accent spine on the leading edge.
    func cardPlate(
        style: OverlayCardStyle,
        scale: CGFloat,
        showsSpine: Bool = true
    ) -> some View {
        modifier(OverlayCardPlate(style: style, scale: scale, showsSpine: showsSpine))
    }
}

// MARK: - Shared Text Pieces

/// Small uppercase accent line above or below a title (time, "Up next",
/// "Presented by", period). The family's second signature after the spine.
struct OverlayCardEyebrow: View {

    let text: String
    let style: OverlayCardStyle
    let scale: CGFloat

    var body: some View {
        Text(text.uppercased())
            .font(.system(
                size: OverlayCardTheme.TypeScale.label(for: style) * scale,
                weight: .semibold,
                design: style.fontDesign.design
            ))
            .tracking(OverlayCardTheme.TypeScale.labelTracking * scale)
            .foregroundColor(style.resolvedAccent.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - OverlayCardWrapLayout

/// Sizes one text block to its natural width, wrapping only once it would
/// exceed `maxWidth`.
///
/// Cards are measured with no size proposal (`fixedSize()` on the display,
/// `fittingSize` for thumbnails). A plain `frame(maxWidth:)` then reports
/// the single-line height of long text, so verses and questions spilled off
/// the plate. This layout asks the block for its ideal size first and, when
/// that is too wide, re-measures it at `maxWidth` so the plate grows to fit
/// every line on every output.
struct OverlayCardWrapLayout: Layout {

    let maxWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let block = subviews.first else { return .zero }
        let limit = min(maxWidth, proposal.width ?? maxWidth)
        let ideal = block.sizeThatFits(.unspecified)
        if ideal.width <= limit {
            return ideal
        }
        let wrapped = block.sizeThatFits(ProposedViewSize(width: limit, height: nil))
        return CGSize(width: limit, height: wrapped.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
