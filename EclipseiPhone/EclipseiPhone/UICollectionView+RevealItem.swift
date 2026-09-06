//
//  UICollectionView+RevealItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UICollectionView {

    /// True when `itemFrame` is not fully inside `visibleRect` and a scroll is needed.
    ///
    /// Both rects are in content coordinates; `visibleRect` should already exclude the
    /// adjusted content inset so a tile tucked under floating chrome counts as hidden.
    static func needsReveal(itemFrame: CGRect, visibleRect: CGRect) -> Bool {
        !visibleRect.contains(itemFrame)
    }

    /// Jumps (no glide) so the item at `indexPath` is fully on screen, unless it is.
    ///
    /// Used when a fullscreen Preview closes: the grid should already be parked on the
    /// tile the user swiped to by the time the modal finishes dismissing.
    func revealItemIfNeeded(at indexPath: IndexPath) {
        layoutIfNeeded()
        guard let frame = layoutAttributesForItem(at: indexPath)?.frame else { return }
        let visible = bounds.inset(by: adjustedContentInset)
        guard Self.needsReveal(itemFrame: frame, visibleRect: visible) else { return }
        scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
    }
}
