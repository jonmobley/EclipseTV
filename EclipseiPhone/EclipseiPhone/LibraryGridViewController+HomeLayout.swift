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
    ///
    /// Home is Recent Shows only. The Logo / Camera / Website row belongs to an
    /// open Show, where those tools act on the Show you're looking at.
    static func visibleHomeSections(
        isShowMode: Bool,
        showsSlideshowRibbon: Bool
    ) -> [HomeSection] {
        guard isShowMode else { return [.shows] }
        var sections: [HomeSection] = [.tools]
        if showsSlideshowRibbon {
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
        return HomeGridLayout { sectionIndex, environment in
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

    /// Smallest tile edge the layout will emit.
    private static let minimumTileSide: CGFloat = 1

    /// Item edge for an `n`-up row, floored to a positive value.
    ///
    /// `NSCollectionLayoutDimension.absolute` throws on a non-positive value. The container
    /// width is briefly zero during early layout (and can be tiny in a narrow split-view
    /// column), which made this subtraction go negative and take the app down.
    private static func columnWidth(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat,
        columns: CGFloat
    ) -> CGFloat {
        let columns = max(columns, 1)
        let totalSpacing = sectionInset * 2 + spacing * (columns - 1)
        let usable = containerWidth - totalSpacing
        return max((usable / columns).rounded(.down), minimumTileSide)
    }

    private static func toolsSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let columns: CGFloat = 3
        let itemWidth = columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: columns
        )
        let aspect = ExternalOutputSettings.orientation.gridCellHeightOverWidth
        let cardHeight = max((itemWidth * aspect).rounded(.down), minimumTileSide)
        // Landscape: Logo / Camera / Website labels sit under the 16:9 cards.
        let captionReserve = ExternalOutputSettings.isVerticalMode
            ? 0
            : LibraryThumbnailCell.landscapeCaptionReserve
        let itemHeight = cardHeight + captionReserve

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
            top: 8, leading: sectionInset,
            bottom: 8, trailing: sectionInset
        )
        return section
    }

    /// Recent Shows tile edge — square, on the same 3-up grid as the tools row.
    static func showsRibbonTileSide(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: 3
        )
    }

    /// Top padding above the Recent Shows header.
    static let showsRibbonTopInset: CGFloat = 20

    /// Recent Shows on Home: horizontal ribbon aligned with tool tile width.
    private static func showsRibbonSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let side = showsRibbonTileSide(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )

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
            top: showsRibbonTopInset, leading: sectionInset,
            bottom: sectionInset, trailing: sectionInset
        )

        section.boundarySupplementaryItems = [Self.sectionHeaderItem()]
        return section
    }

    /// Horizontal slide strip while a Slideshow with Live Ribbon is active.
    private static func slideshowRibbonSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let full = columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: 3
        )
        let side = max((full * 0.72).rounded(.down), minimumTileSide)

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

        section.boundarySupplementaryItems = [Self.sectionHeaderItem()]
        return section
    }

    /// Nominal section-header height; also used to place the empty-state hint.
    static let sectionHeaderEstimatedHeight: CGFloat = 28

    private static func sectionHeaderItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(sectionHeaderEstimatedHeight)
        )
        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    /// Vertical grid of Show media (same column/aspect math as tools).
    private static func showMediaSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let orientation = ExternalOutputSettings.orientation
        let columns = max(CGFloat(orientation.gridColumnCount(
            forWidth: containerWidth, sectionInset: sectionInset, spacing: spacing
        )), 1)
        let itemWidth = columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: columns
        )
        let itemHeight = max(
            (itemWidth * orientation.gridCellHeightOverWidth).rounded(.down), minimumTileSide
        )

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
