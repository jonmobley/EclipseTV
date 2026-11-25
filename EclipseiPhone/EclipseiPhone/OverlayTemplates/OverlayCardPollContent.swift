//
//  OverlayCardPollContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Stacked question + option rows for the Poll / Question card
//               template.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardPollContent

/// Dedicated poll chrome for `.pollPrompt` card overlays.
///
/// Metrics match `OverlayCardView`'s 1080p reference (`scale == 1.0`).
struct OverlayCardPollContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig
    var scale: CGFloat = 1.0

    // MARK: - Constants

    private enum Metric {
        static let questionSpacing: CGFloat = 20
        static let optionSpacing: CGFloat = 12
        static let badgeSize: CGFloat = 44
    }

    private typealias Space = OverlayCardTheme.Space

    private var style: OverlayCardStyle { config.resolvedStyle }

    private typealias Key = OverlayCardTemplate.PollKey

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.questionSpacing * scale) {
            Text(questionText)
                .font(.system(
                    size: style.titleSize * scale,
                    weight: style.titleWeight.weight,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Metric.optionSpacing * scale) {
                ForEach(filledOptions, id: \.key) { option in
                    optionRow(letter: option.letter, text: option.text)
                }
            }
        }
        .padding(.leading, (Space.padH + Space.spine) * scale)
        .padding(.trailing, Space.padH * scale)
        .padding(.vertical, Space.padV * scale)
        .frame(
            minWidth: Space.minPlateWidth * scale,
            maxWidth: Space.maxPlateWidth * scale,
            alignment: .leading
        )
        .cardPlate(style: style, scale: scale)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Content

    private var questionText: String {
        OverlayCardTemplate.trimmed(config.fields, Key.question) ?? "Question"
    }

    private var filledOptions: [(key: String, letter: String, text: String)] {
        Key.optionKeys.compactMap { key in
            guard let text = OverlayCardTemplate.trimmed(config.fields, key)
            else { return nil }
            return (key, Key.optionLetter(key), text)
        }
    }

    /// Letter badge in the accent, letter in the plate color so it reads on
    /// amber and gold as well as teal.
    private func optionRow(letter: String, text: String) -> some View {
        HStack(spacing: 16 * scale) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: max(4, style.cornerRadius * 0.5) * scale,
                    style: .continuous
                )
                .fill(style.resolvedAccent.color)
                Text(letter)
                    .font(.system(
                        size: OverlayCardTheme.TypeScale.label(for: style) * scale,
                        weight: .heavy,
                        design: style.fontDesign.design
                    ))
                    .foregroundColor(style.backgroundColor.color)
            }
            .frame(
                width: Metric.badgeSize * scale,
                height: Metric.badgeSize * scale
            )

            Text(text)
                .font(.system(
                    size: style.subtitleSize * scale,
                    weight: .medium,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }

}
