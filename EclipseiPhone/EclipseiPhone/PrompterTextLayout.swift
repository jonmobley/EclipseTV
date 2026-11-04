//
//  PrompterTextLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Where the reading guide sits in the script, independent of font size or width.
///
/// The operator stage and the output stage wrap the script differently, so they
/// share a position by character rather than by scroll offset. `lineFraction` is how
/// far down that character's line the guide is (0 = top, 1 = bottom).
struct PrompterReadingAnchor: Equatable {
    var characterIndex: Int
    var lineFraction: CGFloat

    static let start = PrompterReadingAnchor(characterIndex: 0, lineFraction: 0)
}

/// A TextKit 1 layout of the script at one font and width, with the maths to turn a
/// text y position into a reading anchor and back.
///
/// Headless by default (`init(script:font:width:)`); a stage can instead wrap its own
/// text view's layout manager so the mapping matches what is drawn exactly.
final class PrompterTextLayout {

    let font: UIFont
    let lineHeight: CGFloat

    private let storage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let container: NSTextContainer

    /// Builds a private layout of `script` wrapped at `width`.
    convenience init(script: String, font: UIFont, width: CGFloat) {
        let storage = NSTextStorage(
            attributedString: PrompterStageMetrics.attributedScript(script, font: font, color: .white)
        )
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let container = NSTextContainer(
            size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        self.init(storage: storage, layoutManager: layoutManager, container: container, font: font)
    }

    /// Wraps an existing text stack (a `UITextView`'s), so anchors map onto what it draws.
    init(storage: NSTextStorage, layoutManager: NSLayoutManager, container: NSTextContainer, font: UIFont) {
        self.storage = storage
        self.layoutManager = layoutManager
        self.container = container
        self.font = font
        self.lineHeight = PrompterStageMetrics.lineHeight(for: font)
    }

    var isEmpty: Bool { storage.length == 0 }

    /// Height of the laid-out script; one line for an empty script.
    var contentHeight: CGFloat {
        guard !isEmpty else { return lineHeight }
        layoutManager.ensureLayout(for: container)
        return max(lineHeight, ceil(layoutManager.usedRect(for: container).height))
    }

    /// Number of wrapped lines (one for an empty script).
    var lineCount: Int {
        max(1, Int((contentHeight / lineHeight).rounded()))
    }

    /// The anchor under a text y position (0 = top of the script).
    func anchor(atTextY y: CGFloat) -> PrompterReadingAnchor {
        guard !isEmpty else { return .start }
        layoutManager.ensureLayout(for: container)
        let clampedY = min(max(0, y), max(0, contentHeight - 0.5))
        let glyph = layoutManager.glyphIndex(
            for: CGPoint(x: 0, y: clampedY), in: container, fractionOfDistanceThroughGlyph: nil
        )
        guard glyph < layoutManager.numberOfGlyphs else {
            return PrompterReadingAnchor(characterIndex: storage.length, lineFraction: 0)
        }
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let fraction = rect.height > 0 ? (clampedY - rect.minY) / rect.height : 0
        return PrompterReadingAnchor(
            characterIndex: layoutManager.characterIndexForGlyph(at: glyph),
            lineFraction: min(max(0, fraction), 1)
        )
    }

    /// Text y position of `anchor` in this layout.
    func textY(for anchor: PrompterReadingAnchor) -> CGFloat {
        guard let rect = lineRect(for: anchor) else { return 0 }
        return rect.minY + rect.height * min(max(0, anchor.lineFraction), 1)
    }

    /// Ordinal of the wrapped line holding `anchor`.
    func lineIndex(for anchor: PrompterReadingAnchor) -> Int {
        guard let rect = lineRect(for: anchor), lineHeight > 0 else { return 0 }
        return Int((rect.minY / lineHeight).rounded())
    }

    /// The wrapped lines around `anchor` (empty strings for blank lines), with the
    /// index of the anchor's own line in the result.
    func lines(
        around anchor: PrompterReadingAnchor,
        before: Int = 1,
        after: Int = 1
    ) -> (lines: [String], currentIndex: Int) {
        guard !isEmpty, let current = lineRect(for: anchor) else { return ([""], 0) }
        let top = max(0, current.minY - CGFloat(before) * lineHeight)
        let bottom = min(contentHeight, current.maxY + CGFloat(after) * lineHeight)
        let bounds = CGRect(x: 0, y: top, width: container.size.width, height: bottom - top)
        let glyphs = layoutManager.glyphRange(forBoundingRect: bounds, in: container)
        var lines: [String] = []
        var currentIndex = 0
        let text = storage.string as NSString
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
            let chars = self.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let line = text.substring(with: chars)
                .trimmingCharacters(in: .newlines)
            if abs(rect.minY - current.minY) < 0.5 { currentIndex = lines.count }
            lines.append(line)
        }
        return lines.isEmpty ? ([""], 0) : (lines, currentIndex)
    }

    private func lineRect(for anchor: PrompterReadingAnchor) -> CGRect? {
        guard !isEmpty else { return nil }
        layoutManager.ensureLayout(for: container)
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return nil }
        let character = min(max(0, anchor.characterIndex), max(0, storage.length - 1))
        let glyph = min(layoutManager.glyphIndexForCharacter(at: character), glyphCount - 1)
        var rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        // An anchor past the last character (after a trailing newline) sits on the
        // extra line fragment TextKit keeps for it.
        if anchor.characterIndex >= storage.length, layoutManager.extraLineFragmentRect.height > 0 {
            rect = layoutManager.extraLineFragmentRect
        }
        return rect
    }
}
