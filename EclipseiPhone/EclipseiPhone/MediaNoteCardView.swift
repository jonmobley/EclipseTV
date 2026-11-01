//
//  MediaNoteCardView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Welcome-style note card without the Getting Started icon badge.
final class MediaNoteCardView: ExpandableNoteCardView {

    init() {
        super.init(horizontalInset: 16, verticalInset: 16)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = CornerRadii.large
        layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var collapsedLineCount: Int { 5 }

    /// Fills the card. Empty `note` shows the tap-to-add placeholder.
    func configure(note: String?) {
        fill(
            note: note?.isEmpty == false ? note : nil,
            textColor: .secondaryLabel,
            placeholder: "Tap to add a note"
        )
    }
}
