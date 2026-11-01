//
//  MediaNoteTextTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct MediaNoteTextTests {

    private let font = UIFont.systemFont(ofSize: 15)

    private func style(ofLine index: Int, in note: String) -> NSParagraphStyle? {
        let text = MediaNoteText.attributed(note, font: font, color: .label)
        let location = note.components(separatedBy: "\n").prefix(index)
            .reduce(0) { $0 + ($1 as NSString).length + 1 }
        return text.attribute(.paragraphStyle, at: location, effectiveRange: nil)
            as? NSParagraphStyle
    }

    @Test(arguments: ["• Item", "◦ Item", "▪ Item", "- Item", "* Item", "– Item", "1. Item", "12) Item"])
    func recognizesListMarkers(line: String) {
        #expect(MediaNoteText.listPrefix(of: line) != nil)
    }

    @Test func tabAfterTheMarkerCounts() {
        #expect(MediaNoteText.listPrefix(of: "•\tItem") == "•\t")
    }

    @Test func nestedItemsKeepTheirLeadingSpaces() {
        #expect(MediaNoteText.listPrefix(of: "  - Item") == "  - ")
    }

    @Test(arguments: ["-5 degrees", "1.5 million", "Plain line", "Buy milk - today", "1 of 3", ""])
    func ignoresEverythingElse(line: String) {
        #expect(MediaNoteText.listPrefix(of: line) == nil)
    }

    @Test func onlyListLinesGetAHangingIndent() throws {
        let note = "Intro line\n• First item\n-5 degrees\n2. Second item"
        #expect(style(ofLine: 0, in: note) == nil)
        #expect(try #require(style(ofLine: 1, in: note)).headIndent > 0)
        #expect(style(ofLine: 2, in: note) == nil)
        #expect(try #require(style(ofLine: 3, in: note)).headIndent > 0)
    }

    @Test func tabStopSitsExactlyAtTheIndent() throws {
        let tabbed = try #require(style(ofLine: 0, in: "•\tItem"))
        #expect(tabbed.tabStops.first?.location == tabbed.headIndent)
    }

    /// The paragraph style overrides the label's mode, so without this a collapsed
    /// list line is clipped mid-word instead of ending in "…".
    @Test func listLinesTruncateWithAnEllipsis() throws {
        #expect(try #require(style(ofLine: 0, in: "• Item")).lineBreakMode == .byTruncatingTail)
    }

    @Test func keepsTheNoteTextUnchanged() {
        let note = "• One\n\n2. Two"
        #expect(MediaNoteText.attributed(note, font: font, color: .label).string == note)
    }

    @Test func wrappedListLinesAreTallerThanOneLine() {
        let note = "• " + String(repeating: "wrapped words ", count: 20)
        let text = MediaNoteText.attributed(note, font: font, color: .label)
        #expect(MediaNoteText.height(of: text, width: 200, lines: 0) > font.lineHeight * 2)
    }

    @Test func fourLinesAreTruncatedAtThree() {
        let text = MediaNoteText.attributed("a\nb\nc\nd", font: font, color: .label)
        #expect(MediaNoteText.isTruncated(text, width: 300, lines: 3))
    }

    @Test func twoLinesAreNotTruncatedAtThree() {
        let text = MediaNoteText.attributed("a\nb", font: font, color: .label)
        #expect(!MediaNoteText.isTruncated(text, width: 300, lines: 3))
    }
}
