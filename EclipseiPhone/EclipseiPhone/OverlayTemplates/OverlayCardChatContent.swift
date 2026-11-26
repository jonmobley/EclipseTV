//
//  OverlayCardChatContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Viewer Question layout: who asked as an accent eyebrow, then
//               the question at title size, on the shared card plate.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardChatContent

/// Viewer Question card.
///
/// The question wraps inside the shared maximum plate width so a long
/// question stays complete instead of shrinking.
struct OverlayCardChatContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    private typealias Space = OverlayCardTheme.Space
    private typealias Key = OverlayCardTemplate.ChatQuestionKey

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
            if let from = fromText {
                OverlayCardEyebrow(text: from, style: style, scale: scale)
            }
            Text(questionText)
                .font(.system(
                    size: style.titleSize * scale,
                    weight: style.titleWeight.weight,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
        }
    }

    // MARK: - Content

    private var questionText: String {
        OverlayCardTemplate.trimmed(config.fields, Key.question) ?? "Question"
    }

    private var fromText: String? {
        OverlayCardTemplate.trimmed(config.fields, Key.from)
    }
}
