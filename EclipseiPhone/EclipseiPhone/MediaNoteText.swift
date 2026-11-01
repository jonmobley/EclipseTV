//
//  MediaNoteText.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Display-only formatting for presenter notes.
///
/// Notes stay plain text everywhere they are stored and synced. List lines just
/// get a hanging indent when drawn, so wrapped lines sit under the item text.
enum MediaNoteText {

    /// Marker and the whitespace after it when `line` is a list line, else nil.
    ///
    /// Leading spaces count, so nested items pasted from Notes still indent.
    /// `-5 degrees` isn't a list line: the marker needs whitespace after it.
    static func listPrefix(of line: String) -> String? {
        guard let match = line.prefixMatch(of: /(?: *)(?:[•◦▪\-*–]|\d+[.)])[ \t]+/) else {
            return nil
        }
        return String(match.output)
    }

    /// `note` in `font` and `color`, with hanging indents on its list lines.
    static func attributed(_ note: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: note,
            attributes: [.font: font, .foregroundColor: color]
        )
        let text = note as NSString
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: .byParagraphs
        ) { line, _, lineRange, _ in
            guard let line, let prefix = listPrefix(of: line) else { return }
            result.addAttribute(
                .paragraphStyle,
                value: hangingStyle(forPrefix: prefix, font: font),
                range: lineRange
            )
        }
        return result
    }

    /// Height of `attributed` at `width`, limited to `lines` (0 means no limit).
    static func height(of attributed: NSAttributedString, width: CGFloat, lines: Int) -> CGFloat {
        let label = UILabel()
        label.attributedText = attributed
        label.numberOfLines = lines
        return label.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
    }

    /// True when `attributed` needs more than `lines` lines at `width`.
    static func isTruncated(_ attributed: NSAttributedString, width: CGFloat, lines: Int) -> Bool {
        let limited = height(of: attributed, width: width, lines: lines)
        return height(of: attributed, width: width, lines: 0) > limited + 0.5
    }

    // MARK: - Private

    /// Indent equal to the prefix's width. A tab after the marker would otherwise
    /// jump to a default stop, so one is set exactly at the indent.
    private static func hangingStyle(forPrefix prefix: String, font: UIFont) -> NSParagraphStyle {
        let measured = prefix.replacingOccurrences(of: "\t", with: " ") as NSString
        let indent = ceil(measured.size(withAttributes: [.font: font]).width)
        let style = NSMutableParagraphStyle()
        style.headIndent = indent
        style.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]
        // A paragraph style overrides the label's own mode, and the default clips
        // the last collapsed line mid-word. Labels still wrap the earlier lines.
        style.lineBreakMode = .byTruncatingTail
        return style
    }
}
