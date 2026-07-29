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
                return Self.showsGridSection(
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

    /// Tools sit on the same column grid as the Show media below them, so the two
    /// bands line up: 2-up for 16:9 Landscape cards, 3-up for 9:16 Vertical ones.
    private static func toolsSection(
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
        let aspect = orientation.gridCellHeightOverWidth
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
        // Fewer columns than tools means the row wraps.
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: sectionInset,
            bottom: 8, trailing: sectionInset
        )
        return section
    }

    /// Top padding above the Recent Shows header.
    static let showsGridTopInset: CGFloat = 20

    /// Target Show-tile edge. Wider panes gain columns instead of bigger tiles.
    private static let showsTilePreferredWidth: CGFloat = 120

    /// Recent Shows columns — 3-up on a phone, more once there's room.
    static func showsGridColumnCount(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> Int {
        let available = containerWidth - sectionInset * 2
        guard available > 0 else { return 3 }
        let fitted = Int(floor((available + spacing) / (showsTilePreferredWidth + spacing)))
        return max(3, fitted)
    }

    /// Recent Shows tile edge — square, derived from the current column count.
    static func showsTileSide(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: CGFloat(showsGridColumnCount(
                containerWidth: containerWidth,
                sectionInset: sectionInset,
                spacing: spacing
            ))
        )
    }

    /// Recent Shows on Home: square tiles wrapping down the page.
    private static func showsGridSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let columns = showsGridColumnCount(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )
        let side = showsTileSide(
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
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(side)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: showsGridTopInset, leading: sectionInset,
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
