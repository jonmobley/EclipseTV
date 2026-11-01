//
//  LiveNoteCardView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Presenter note for the live item, docked under the live preview chrome.
///
/// The host pins an explicit height so the card can reserve its strip of chrome
/// before layout runs, and asks `height(forWidth:maxHeight:)` for the value.
final class LiveNoteCardView: ExpandableNoteCardView {

    private static let compactLineCount = 3
    private static let regularLineCount = 5

    init() {
        super.init(horizontalInset: 14, verticalInset: 12)
        backgroundColor = .secondarySystemBackground
        layer.applyContinuousCorner(radius: CornerRadii.card)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lines shown while collapsed. An iPad has the room for more.
    static func collapsedLineCount(horizontalSizeClass: UIUserInterfaceSizeClass) -> Int {
        horizontalSizeClass == .regular ? regularLineCount : compactLineCount
    }

    override var collapsedLineCount: Int {
        // Plus/Max landscape is `.regular` width — still phone chrome, not iPad.
        Self.collapsedLineCount(
            horizontalSizeClass: traitCollection.prefersRegularNoteLayout ? .regular : .compact
        )
    }

    /// Fills the card with `note`.
    func configure(note: String) {
        fill(note: note, textColor: .label)
    }
}
