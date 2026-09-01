//
//  LibraryThumbnailCell+Select.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Show Grid Select Mode

extension LibraryThumbnailCell {

    /// Replaces the ⋯ control with a checkmark circle while multi-selecting.
    ///
    /// Live / non-selectable tiles keep their existing chrome and get no circle.
    /// - Parameters:
    ///   - enabled: Whether the grid is in select mode.
    ///   - isSelected: Whether this tile is in the current selection.
    ///   - isSelectable: False for live tiles, slideshows, and the Add tile.
    func setShowSelectMode(
        enabled: Bool,
        isSelected: Bool,
        isSelectable: Bool
    ) {
        guard enabled else { return }
        clearMoreMenu()
        guard isSelectable else {
            selectionBadge.isHidden = true
            return
        }
        let symbol = isSelected ? "checkmark.circle.fill" : "circle"
        selectionBadge.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        )
        selectionBadge.tintColor = isSelected ? .systemBlue : .white
        selectionBadge.backgroundColor = isSelected
            ? .white
            : UIColor.black.withAlphaComponent(0.35)
        selectionBadge.isHidden = false
        cardView.bringSubviewToFront(selectionBadge)
        cardView.layer.borderWidth = isSelected ? 3 : 0
        cardView.layer.borderColor = isSelected
            ? UIColor.systemBlue.cgColor
            : UIColor.clear.cgColor
    }
}
