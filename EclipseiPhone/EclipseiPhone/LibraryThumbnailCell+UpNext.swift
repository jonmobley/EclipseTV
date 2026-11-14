//
//  LibraryThumbnailCell+UpNext.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Up Next (Blackout cue)

extension LibraryThumbnailCell {

    private static var upNextTag: Int { 7_311 }

    /// Shows the "UP NEXT" pill on the tile cued to follow Blackout.
    func setUpNext(_ upNext: Bool) {
        let existing = cardView.viewWithTag(Self.upNextTag)
        guard upNext else {
            existing?.removeFromSuperview()
            return
        }
        if let existing {
            cardView.bringSubviewToFront(existing)
            return
        }
        let pill = PaddedLabel()
        pill.tag = Self.upNextTag
        pill.text = "UP NEXT"
        pill.font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: .systemFont(ofSize: 11, weight: .bold))
        pill.adjustsFontForContentSizeCategory = true
        pill.textColor = .white
        pill.backgroundColor = .systemIndigo
        pill.layer.cornerRadius = 6
        pill.layer.masksToBounds = true
        pill.isUserInteractionEnabled = false
        pill.isAccessibilityElement = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            pill.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
        ])
        if let label = accessibilityLabel, !label.contains("up next") {
            accessibilityLabel = label + ", up next after Blackout"
        }
    }
}
