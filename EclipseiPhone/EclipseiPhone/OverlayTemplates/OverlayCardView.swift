//
//  OverlayCardView.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: The single visual definition for a template-driven card overlay
//               (spine + optional icon + text stack on the shared plate). Used
//               directly in the preview and external display, and rasterized
//               for thumbnails and the Core Image program compositor so every
//               output looks identical.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardView

/// Visual for a template-driven card overlay.
///
/// Most templates render as the standard card: accent spine, optional inline
/// icon, and a text stack (eyebrow, title, subtitle). Dedicated layouts cover
/// QR, lower thirds, scripture, polls, chat, sponsors, and scoreboards; all of
/// them sit on the same ``OverlayCardPlate``.
/// All sizing is multiplied by `scale`, where `scale == 1.0` is tuned for a
/// 1080p render target.
///
/// Thread Safety: Main thread only - SwiftUI view component.
struct OverlayCardView: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    private typealias Space = OverlayCardTheme.Space

    /// The operator-chosen appearance for this card.
    private var style: OverlayCardStyle { config.resolvedStyle }

    // MARK: - Body

    var body: some View {
        if config.template == .qrCode {
            OverlayCardQRContent(config: config, scale: scale)
        } else if config.template.usesLowerThirdLayout {
            OverlayCardLowerThirdContent(config: config, scale: scale)
        } else if config.template.usesScriptureLayout {
            OverlayCardScriptureContent(config: config, scale: scale)
        } else if config.template.usesPollLayout {
            OverlayCardPollContent(config: config, scale: scale)
        } else if config.template.usesChatLayout {
            OverlayCardChatContent(config: config, scale: scale)
        } else if config.template.usesSponsorLayout {
            OverlayCardSponsorContent(config: config, scale: scale)
        } else if config.template.usesScoreboardLayout {
            OverlayCardScoreboardContent(config: config, scale: scale)
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        HStack(alignment: .center, spacing: Space.inlineGap * scale) {
            if style.showsIcon {
                inlineIcon
            }
            textStack
        }
        .padding(.leading, (Space.padH + Space.spine) * scale)
        .padding(.trailing, Space.padH * scale)
        .padding(.vertical, Space.padV * scale)
        .frame(maxWidth: Space.maxPlateWidth * scale, alignment: alignment)
        .cardPlate(style: style, scale: scale)
        .fixedSize()
    }

    // MARK: - Subviews

    /// Icon drawn inline in the accent color, sized to the title's cap height.
    /// No circle: the icon is a word, not a button.
    private var inlineIcon: some View {
        Image(systemName: config.cardIcon)
            .font(.system(size: style.titleSize * 0.78 * scale, weight: .semibold))
            .foregroundColor(style.resolvedAccent.color)
            .frame(width: style.titleSize * 0.9 * scale)
    }

    @ViewBuilder
    private var textStack: some View {
        let eyebrowFirst = config.template.showsTitleAsEyebrow
        let big = eyebrowFirst ? (config.resolvedSubtitle ?? config.resolvedTitle)
                               : config.resolvedTitle
        VStack(alignment: style.textAlignment.horizontal, spacing: Space.lineGap * scale) {
            if eyebrowFirst, config.resolvedSubtitle != nil {
                OverlayCardEyebrow(text: config.resolvedTitle, style: style, scale: scale)
                    .padding(.bottom, (Space.stackGap - Space.lineGap) * scale)
            }
            Text(big)
                .font(.system(size: style.titleSize * scale,
                              weight: style.titleWeight.weight,
                              design: style.fontDesign.design))
                .foregroundColor(style.textColor.color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if !eyebrowFirst, let subtitle = config.resolvedSubtitle {
                Text(subtitle)
                    .font(.system(size: style.subtitleSize * scale,
                                  weight: .regular, design: style.fontDesign.design))
                    .foregroundColor(style.subtitleColor.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .multilineTextAlignment(style.textAlignment.multiline)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var alignment: Alignment {
        switch style.textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Rasterization

extension OverlayCardView {

    /// Renders the card to a `UIImage` for thumbnails and Core Image compositing.
    ///
    /// Uses `ImageRenderer` so the rasterized card matches the live SwiftUI view
    /// exactly. The renderer scale is fixed at 1 so the resulting bitmap's pixel
    /// size equals its point size, keeping corner-placement math predictable.
    ///
    /// The bitmap is larger than the plate by ``rasterPadding(scale:)`` on every
    /// side so the drop shadow survives; callers subtract that border when
    /// they position the card. The renderer is also handed the plate's
    /// maximum width so wrapping text (Scripture, questions) measures its full
    /// height instead of one line.
    ///
    /// - Parameters:
    ///   - config: The card configuration to render.
    ///   - scale: Size multiplier (1.0 == 1080p reference).
    /// - Returns: The rasterized card, or nil if rendering fails.
    @MainActor
    static func rasterize(config: OverlayCardConfig, scale: CGFloat) -> UIImage? {
        let pad = rasterPadding(scale: scale)
        let renderer = ImageRenderer(
            content: OverlayCardView(config: config, scale: scale).padding(pad)
        )
        renderer.proposedSize = ProposedViewSize(
            width: OverlayCardTheme.Space.maxPlateWidth * scale + pad * 2,
            height: nil
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// Transparent border around a rasterized card that holds its shadow.
    ///
    /// - Parameter scale: Size multiplier (1.0 == 1080p reference).
    /// - Returns: The border width in points on each side.
    static func rasterPadding(scale: CGFloat) -> CGFloat {
        OverlayCardTheme.Shadow.padding * scale
    }
}
