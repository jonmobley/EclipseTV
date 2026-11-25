//
//  OverlayCardSponsorContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Centered "Presented by" end-card layout for sponsor overlays
//               on the shared card plate (no spine: the card is symmetrical).
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardSponsorContent

/// Presented By end card: eyebrow, sponsor name, optional tagline, centered.
struct OverlayCardSponsorContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    private typealias Space = OverlayCardTheme.Space
    private typealias Key = OverlayCardTemplate.SponsorKey

    /// Extra horizontal room so the centered name breathes on the plate.
    private static let paddingH: CGFloat = 56

    private var style: OverlayCardStyle { config.resolvedStyle }

    // MARK: - Body

    var body: some View {
        VStack(spacing: Space.stackGap * scale) {
            OverlayCardEyebrow(text: "Presented by", style: style, scale: scale)
            Text(sponsorName)
                .font(.system(
                    size: style.titleSize * scale,
                    weight: style.titleWeight.weight,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let tagline = taglineText {
                Text(tagline)
                    .font(.system(
                        size: style.subtitleSize * scale,
                        weight: .regular,
                        design: style.fontDesign.design
                    ))
                    .foregroundColor(style.subtitleColor.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Self.paddingH * scale)
        .padding(.vertical, Space.padV * scale)
        .frame(
            minWidth: Space.minPlateWidth * scale,
            maxWidth: Space.maxPlateWidth * scale
        )
        .cardPlate(style: style, scale: scale, showsSpine: false)
        .fixedSize()
    }

    // MARK: - Content

    private var sponsorName: String {
        OverlayCardTemplate.trimmed(config.fields, Key.name) ?? "Sponsor"
    }

    private var taglineText: String? {
        OverlayCardTemplate.trimmed(config.fields, Key.tagline)
    }
}
