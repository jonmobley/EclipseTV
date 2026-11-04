//
//  PrompterStageMetrics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Sizes and defaults shared by the Prompter's operator stage and its output stage.
enum PrompterStageMetrics {

    /// Operator text size (points, not Dynamic Type): set explicitly by the presenter.
    static let operatorFontRange: ClosedRange<CGFloat> = 20...120
    static let operatorFontStep: CGFloat = 4

    /// Speed stepper increment.
    static let speedStep: Double = 0.25

    /// Output text never drops below this, even on a small canvas.
    static let minimumOutputFontSize: CGFloat = 40
    /// Output size is this fraction of the canvas's shorter side (~73 pt at 1080p).
    static let outputFontFraction: CGFloat = 0.068
    /// Side inset of the output text as a fraction of the canvas width.
    static let outputHorizontalInsetFraction: CGFloat = 0.08

    /// Fraction of the stage height covered by each fade at the top and bottom.
    static let fadeFraction: CGFloat = 0.18

    /// Widest the operator text runs on a large pane, so lines stay readable.
    static let maximumOperatorTextWidth: CGFloat = 900

    /// Default operator text size: larger on an iPad on a stand.
    static func defaultOperatorFontSize(isPad: Bool) -> CGFloat {
        isPad ? 56 : 32
    }

    static func clampedOperatorFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, operatorFontRange.lowerBound), operatorFontRange.upperBound)
    }

    static func clampedSpeed(_ speed: Double) -> Double {
        min(max(speed, PrompterScrollEngine.minimumSpeed), PrompterScrollEngine.maximumSpeed)
    }

    /// Space above the first line so it can rest on the reading guide.
    static func topInset(viewportHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight / 2 - lineHeight / 2)
    }

    /// Furthest the script scrolls: the last line on the reading guide.
    static func maxOffset(contentHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, contentHeight - lineHeight)
    }

    /// Output text size for a canvas (the rotated canvas in Vertical mode).
    static func outputFontSize(in canvas: CGSize) -> CGFloat {
        max(minimumOutputFontSize, min(canvas.width, canvas.height) * outputFontFraction)
    }

    static func outputTextInset(for canvas: CGSize) -> CGFloat {
        canvas.width * outputHorizontalInsetFraction
    }

    /// The Prompter typeface at `size`.
    static func font(ofSize size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    /// Uniform line height for `font`, so every line fragment is the same height
    /// and line snapping holds.
    static func lineHeight(for font: UIFont) -> CGFloat {
        let measured = font.lineHeight
        return measured > 0
            ? ceil(measured)
            : PrompterScrollEngine.estimatedLineHeight(fontSize: font.pointSize)
    }

    /// Script text styled for a stage: fixed line height, no paragraph spacing.
    static func attributedScript(_ script: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        let height = lineHeight(for: font)
        paragraph.minimumLineHeight = height
        paragraph.maximumLineHeight = height
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: script,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        )
    }
}
