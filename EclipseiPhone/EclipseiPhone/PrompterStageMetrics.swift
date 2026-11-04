//
//  PrompterStageMetrics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Sizes and defaults shared by the Prompter's operator card and its output stage.
///
/// Text size is measured on the show's canvas (1920 wide in Landscape, 1080 in
/// Vertical), the way the Mac app does it. Every stage scales that by its own width,
/// so the card on the phone and the picture on the display wrap identically.
enum PrompterStageMetrics {

    /// Canvas points: the Mac's range and default.
    static let canvasFontRange: ClosedRange<CGFloat> = 24...160
    static let canvasFontStep: CGFloat = 8
    static let defaultCanvasFontSize: CGFloat = 60

    /// Speed stepper increment.
    static let speedStep: Double = 0.25

    /// Side inset of the text as a fraction of the stage width.
    static let textInsetFraction: CGFloat = 0.08

    /// Fraction of the stage height covered by each fade at the top and bottom.
    static let fadeFraction: CGFloat = 0.18

    /// Width of the show's canvas that `canvasFontRange` is measured on.
    static func referenceCanvasWidth(isVertical: Bool) -> CGFloat {
        isVertical ? 1080 : 1920
    }

    static func clampedCanvasFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, canvasFontRange.lowerBound), canvasFontRange.upperBound)
    }

    static func clampedSpeed(_ speed: Double) -> Double {
        min(max(speed, PrompterScrollEngine.minimumSpeed), PrompterScrollEngine.maximumSpeed)
    }

    /// Side inset for a stage of `size`.
    static func textInset(for size: CGSize) -> CGFloat {
        size.width * textInsetFraction
    }

    /// Width of the text column on a stage `stageWidth` wide.
    static func textWidth(forStageWidth stageWidth: CGFloat) -> CGFloat {
        max(1, stageWidth * (1 - 2 * textInsetFraction))
    }

    /// Point size on a stage whose text column is `textWidth` wide, for a canvas size.
    static func stageFontSize(
        canvasFontSize: CGFloat,
        textWidth: CGFloat,
        isVertical: Bool
    ) -> CGFloat {
        let referenceTextWidth = Self.textWidth(forStageWidth: referenceCanvasWidth(isVertical: isVertical))
        return max(6, canvasFontSize * textWidth / referenceTextWidth)
    }

    /// Space above the first line so it can rest on the reading guide.
    static func topInset(viewportHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight / 2 - lineHeight / 2)
    }

    /// Furthest the script scrolls: the last line on the reading guide.
    static func maxOffset(contentHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, contentHeight - lineHeight)
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
