//
//  ExpandableNoteCardFadeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct ExpandableNoteCardFadeTests {

    private let longNote = (1...40).map { "Line \($0)" }.joined(separator: "\n")

    private func card(note: String, expanded: Bool) -> ExpandableNoteCardView {
        let card = ExpandableNoteCardView(horizontalInset: 12, verticalInset: 10)
        card.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        card.fill(note: note, textColor: .label)
        card.setExpanded(expanded)
        card.layoutIfNeeded()
        return card
    }

    private func scrollView(in root: UIView) -> UIScrollView? {
        if let found = root as? NoteCardScrollView { return found }
        return root.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    @Test func fadesWhileMoreOfTheNoteIsBelow() {
        #expect(card(note: longNote, expanded: true).fadeDepth == 32)
    }

    @Test func fadeLeavesAtTheEndOfTheNote() throws {
        let card = card(note: longNote, expanded: true)
        let scroll = try #require(scrollView(in: card))
        let end = scroll.contentSize.height - scroll.bounds.height
        scroll.contentOffset.y = end - 10
        #expect(card.fadeDepth == 10)
        scroll.contentOffset.y = end
        #expect(card.fadeDepth == 0)
    }

    @Test func noFadeWhenCollapsed() {
        #expect(card(note: longNote, expanded: false).fadeDepth == 0)
    }

    @Test func noFadeWhenTheNoteFits() {
        #expect(card(note: "Short note", expanded: true).fadeDepth == 0)
    }
}
