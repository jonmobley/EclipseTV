//
//  OverlayCardScriptureContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Verse-plate layout for the Scripture card template: the
//               reference as an accent eyebrow above the passage, on the
//               shared card plate.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardScriptureContent

/// Scripture card: reference eyebrow, then the verse at reading size.
///
/// The verse wraps inside the shared maximum plate width and the plate grows
/// to fit it, so long passages stay complete on every output.
struct OverlayCardScriptureContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    private typealias Space = OverlayCardTheme.Space
    private typealias Key = OverlayCardTemplate.ScriptureKey

    /// Extra line spacing for multi-line verse text, at the reference scale.
    private static let verseLineSpacing: CGFloat = 6

    private var style: OverlayCardStyle { config.resolvedStyle }

    // MARK: - Body

    var body: some View {
        OverlayCardWrapLayout(maxWidth: textMaxWidth * scale) {
            textBlock
        }
        .padding(.leading, (Space.padH + Space.spine) * scale)
        .padding(.trailing, Space.padH * scale)
        .padding(.vertical, Space.padV * scale)
        .cardPlate(style: style, scale: scale)
    }

    // MARK: - Subviews

    /// Width left for text once the plate's padding and spine are taken.
    private var textMaxWidth: CGFloat {
        Space.maxPlateWidth - Space.padH * 2 - Space.spine
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Space.stackGap * scale) {
            reference
            Text(verseText)
                .font(.system(
                    size: style.subtitleSize * scale,
                    weight: .regular,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
                .multilineTextAlignment(.leading)
                .lineSpacing(Self.verseLineSpacing * scale)
        }
    }

    /// The reference line uses the title size so the operator's size control
    /// still applies, styled as the family's uppercase accent eyebrow.
    private var reference: some View {
        Text(referenceText.uppercased())
            .font(.system(
                size: style.titleSize * scale,
                weight: .semibold,
                design: style.fontDesign.design
            ))
            .tracking(OverlayCardTheme.TypeScale.labelTracking * scale)
            .foregroundColor(style.resolvedAccent.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: - Content

    private var referenceText: String {
        OverlayCardTemplate.trimmed(config.fields, Key.reference) ?? "Scripture"
    }

    private var verseText: String {
        OverlayCardTemplate.trimmed(config.fields, Key.verse)
            ?? "Enter verse text"
    }
}
