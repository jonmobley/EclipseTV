//
//  HomeGridLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Home / Show compositional layout that lifts the tile being dragged in
/// arrange mode, so the moving tile reads as picked up off the grid.
final class HomeGridLayout: UICollectionViewCompositionalLayout {

    private static let liftScale: CGFloat = 1.08

    override func layoutAttributesForInteractivelyMovingItem(
        at indexPath: IndexPath,
        withTargetPosition position: CGPoint
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.layoutAttributesForInteractivelyMovingItem(
            at: indexPath,
            withTargetPosition: position
        )
        attributes.transform = CGAffineTransform(
            scaleX: Self.liftScale,
            y: Self.liftScale
        )
        attributes.alpha = 0.95
        // Above the tiles it passes over, including section headers.
        attributes.zIndex = 100
        return attributes
    }
}
