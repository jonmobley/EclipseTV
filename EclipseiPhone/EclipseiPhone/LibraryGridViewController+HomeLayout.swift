//
//  LibraryGridViewController+HomeLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Compositional Layout

extension LibraryGridViewController {

    enum HomeSection: Hashable {
        case tools
        case slideshowRibbon
        case shows
    }

    /// Section order for the current Home / Show / live-ribbon state.
    static func visibleHomeSections(
        isShowMode: Bool,
        showsSlideshowRibbon: Bool
    ) -> [HomeSection] {
        var sections: [HomeSection] = [.tools]
        if isShowMode, showsSlideshowRibbon {
            sections.append(.slideshowRibbon)
        }
        sections.append(.shows)
        return sections
    }

    /// Tools row (3-up) + optional live slideshow ribbon + Recent/Show grid.
    static func makeHomeLayout(
        sectionInset: CGFloat,
        spacing: CGFloat,
        isShowMode: Bool,
        showsSlideshowRibbon: Bool
    ) -> UICollectionViewCompositionalLayout {
        let visible = visibleHomeSections(
            isShowMode: isShowMode,
            showsSlideshowRibbon: showsSlideshowRibbon
        )
        return UICollectionViewCompositionalLayout { sectionIndex, environment in
            let width = environment.container.effectiveContentSize.width
            guard visible.indices.contains(sectionIndex) else { return nil }
            switch visible[sectionIndex] {
            case .tools:
                return Self.toolsSection(
                    containerWidth: width,
                    sectionInset: sectionInset,
                    spacing: spacing
                )
            case .slideshowRibbon:
                return Self.slideshowRibbonSection(
                    containerWidth: width,
                    sectionInset: sectionInset,
                    spacing: spacing
                )
            case .shows:
                if isShowMode {
                    return Self.showMediaSection(
                        containerWidth: width,
                        sectionInset: sectionInset,
                        spacing: spacing
                    )
                }
                return Self.showsRibbonSection(
                    containerWidth: width,
                    sectionInset: sectionInset,
                    spacing: spacing
                )
            }
        }
    }

    private static func toolsSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let columns: CGFloat = 3
        let totalSpacing = sectionInset * 2 + spacing * (columns - 1)
        let itemWidth = ((containerWidth - totalSpacing) / columns).rounded(.down)
        let aspect = ExternalOutputSettings.orientation.gridCellHeightOverWidth
        let itemHeight = (itemWidth * aspect).rounded(.down)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: Int(columns)
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: sectionInset, leading: sectionInset,
            bottom: 8, trailing: sectionInset
        )
        return section
    }

    private static func showsRibbonSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        // Match tool tile width so the ribbon aligns with the row above.
        let columns: CGFloat = 3
        let totalSpacing = sectionInset * 2 + spacing * (columns - 1)
        let side = ((containerWidth - totalSpacing) / columns).rounded(.down)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(side),
            heightDimension: .absolute(side)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(side),
            heightDimension: .absolute(side)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitems: [item]
        )

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: sectionInset,
            bottom: sectionInset, trailing: sectionInset
        )

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(28)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]
        return section
    }

    /// Horizontal slide strip while a Slideshow with Live Ribbon is active.
    private static func slideshowRibbonSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let columns: CGFloat = 3
        let totalSpacing = sectionInset * 2 + spacing * (columns - 1)
        let side = ((containerWidth - totalSpacing) / columns).rounded(.down) * 0.72

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(side),
            heightDimension: .absolute(side)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(side),
            heightDimension: .absolute(side)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitems: [item]
        )

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: sectionInset,
            bottom: 4, trailing: sectionInset
        )

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(28)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]
        return section
    }

    /// Vertical grid of Show media (same column/aspect math as tools).
    private static func showMediaSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let orientation = ExternalOutputSettings.orientation
        let columns = CGFloat(orientation.gridColumnCount(
            forWidth: containerWidth, sectionInset: sectionInset, spacing: spacing
        ))
        let totalSpacing = sectionInset * 2 + spacing * (columns - 1)
        let itemWidth = ((containerWidth - totalSpacing) / columns).rounded(.down)
        let itemHeight = (itemWidth * orientation.gridCellHeightOverWidth).rounded(.down)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: Int(columns)
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: sectionInset,
            bottom: sectionInset, trailing: sectionInset
        )
        return section
    }
}
