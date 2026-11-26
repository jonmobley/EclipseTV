//
//  OverlayCardScoreboardContent+ScoreAdjust.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Operator − / + flanking helpers for live scoreboard scores.
//  Thread Safety: Main thread only - SwiftUI view helpers.
//

import SwiftUI

// MARK: - Score Adjust

extension OverlayCardScoreboardContent {

    /// Score digits, optionally flanked by operator − / + without shifting layout.
    @ViewBuilder
    func scoreValue(
        _ score: Int,
        key: String,
        fontSize: CGFloat
    ) -> some View {
        let hitPad = flankButtonSize + flankSpacing
        Text("\(score)")
            .font(.system(
                size: fontSize,
                weight: style.titleWeight.weight,
                design: style.fontDesign.design
            ))
            .foregroundColor(labelColor(style.textColor.color))
            .monospacedDigit()
            .overlay(alignment: .leading) {
                if interactionOverlay, onAdjustScore != nil {
                    flankingButton("minus", key: key, delta: -1)
                        .offset(x: -hitPad)
                }
            }
            .overlay(alignment: .trailing) {
                if interactionOverlay, onAdjustScore != nil {
                    flankingButton("plus", key: key, delta: 1)
                        .offset(x: hitPad)
                }
            }
            // Expand tap targets past the digit without changing parent layout.
            .padding(.horizontal, interactionOverlay ? hitPad : 0)
            .contentShape(Rectangle())
            .padding(.horizontal, interactionOverlay ? -hitPad : 0)
            .allowsHitTesting(interactionOverlay && onAdjustScore != nil)
    }

    var flankButtonSize: CGFloat {
        max(28, 34 * scale)
    }

    var flankSpacing: CGFloat {
        max(4, 6 * scale)
    }

    func flankingButton(
        _ systemImage: String,
        key: String,
        delta: Int
    ) -> some View {
        Button {
            onAdjustScore?(key, delta)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: max(12, 14 * scale), weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: flankButtonSize, height: flankButtonSize)
                .background(
                    RoundedRectangle(
                        cornerRadius: max(6, 8 * scale),
                        style: .continuous
                    )
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: max(6, 8 * scale),
                            style: .continuous
                        )
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(delta > 0 ? "Increase score" : "Decrease score")
    }

    /// Hides plate copy when this instance is only the operator hit overlay.
    func labelColor(_ color: Color) -> Color {
        interactionOverlay ? .clear : color
    }
}
