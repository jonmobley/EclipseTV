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
        case hero
        case tools
        case slideshowRibbon
        case shows
    }

    /// Section order for one page. Home and Show are separate collection views,
    /// so these lists never share a cell.
    ///
    /// Home: hero carousel, then Recent. A Show uses one media grid
    /// (tools + members from `surfaceIds`); no fixed tools band.
    /// Phone landscape docks the live slideshow ribbon under the leading
    /// preview, so pass `showsSlideshowRibbon: false` for that chrome.
    static func visibleHomeSections(
        isShowMode: Bool,
        showsSlideshowRibbon: Bool
    ) -> [HomeSection] {
        guard isShowMode else { return [.hero, .shows] }
        var sections: [HomeSection] = []
        if showsSlideshowRibbon {
            sections.append(.slideshowRibbon)
        }
        sections.append(.shows)
        return sections
    }

    /// In-grid ribbon is portrait-only. Phone landscape docks it under the
    /// leading live preview so the Show grid can scroll on its own.
    static func showsInGridSlideshowRibbon(
        liveRibbon: Bool,
        sideBySideChrome: Bool
    ) -> Bool {
        liveRibbon && !sideBySideChrome
    }

    /// Home / Show layout inputs, re-read on every layout pass.
    struct HomeLayoutState {
        var isShowMode: Bool
        var showsSlideshowRibbon: Bool
        /// Home Recent format chips — taller header estimate when both formats exist.
        var showsRecentFormatFilter: Bool = false

        /// Home with nothing playing — the state to assume once the controller is gone.
        static let home = HomeLayoutState(
            isShowMode: false,
            showsSlideshowRibbon: false
        )

        var sections: [HomeSection] {
            LibraryGridViewController.visibleHomeSections(
                isShowMode: isShowMode,
                showsSlideshowRibbon: showsSlideshowRibbon
            )
        }
    }

    /// Tools row (3-up) + optional live slideshow ribbon + Recent/Show grid.
    ///
    /// `state` is sampled per pass rather than captured once. The data source derives
    /// its section count from the same mutable state (open Show, live slideshow) on
    /// every query, so a layout holding a snapshot of it can be asked for a section
    /// it doesn't know — which UIKit treats as a fatal client error, not a glitch.
    static func makeHomeLayout(
        sectionInset: CGFloat,
        spacing: CGFloat,
        state: @escaping () -> HomeLayoutState
    ) -> UICollectionViewCompositionalLayout {
        HomeGridLayout { sectionIndex, environment in
            let width = environment.container.effectiveContentSize.width
            let live = state()
            let visible = live.sections
            guard visible.indices.contains(sectionIndex) else {
                return Self.unknownSection()
            }
            switch visible[sectionIndex] {
            case .hero:
                return Self.heroSection(sectionInset: sectionInset)
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
                if live.isShowMode {
                    return Self.showMediaSection(
                        containerWidth: width,
                        sectionInset: sectionInset,
                        spacing: spacing
                    )
                }
                return Self.showsGridSection(
                    containerWidth: width,
                    sectionInset: sectionInset,
                    spacing: spacing,
                    showsFormatFilter: live.showsRecentFormatFilter
                )
            }
        }
    }

    /// Estimated height of the Home hero carousel (card + page dots).
    static var heroEstimatedHeight: CGFloat {
        HomeHeroCarouselCell.cardHeight + 28
    }

    /// Marketing carousel above Recent.
    private static func heroSection(
        sectionInset: CGFloat
    ) -> NSCollectionLayoutSection {
        let height = heroEstimatedHeight
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(height)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: itemSize,
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: sectionInset,
            bottom: 4, trailing: sectionInset
        )
        return section
    }

    /// Stand-in for a section index the layout can't name.
    ///
    /// The provider must not return nil for a section UIKit has content to render:
    /// it raises `NSInternalInconsistencyException` ("Invalid section definition")
    /// rather than skipping the section. This degrades a layout / data-source
    /// disagreement into a hairline row that the next invalidation corrects.
    private static func unknownSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(minimumTileSide)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        return NSCollectionLayoutSection(
            group: NSCollectionLayoutGroup.horizontal(
                layoutSize: size,
                subitems: [item]
            )
        )
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
        let columns = homeGridColumnCount(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )
        let card = homeTileSize(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )
        let itemWidth = card.width
        let itemHeight = card.height

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
            count: columns
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
    static let showsGridTopInset: CGFloat = 12

    /// Columns for every tile band in the home collection view, from the Display
    /// Mode: 2-up for 16:9 Landscape, 3-up for 9:16 Vertical (4-up when the phone
    /// is turned), gaining further columns on iPad rather than growing the tile.
    static func homeGridColumnCount(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation
    ) -> Int {
        max(orientation.gridColumnCount(
            forWidth: containerWidth, sectionInset: sectionInset, spacing: spacing
        ), 1)
    }

    /// Tile size for an open Show's grid: 16:9 in Landscape, 9:16 in Vertical.
    static func homeTileSize(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation
    ) -> CGSize {
        let width = columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: CGFloat(homeGridColumnCount(
                containerWidth: containerWidth,
                sectionInset: sectionInset,
                spacing: spacing,
                orientation: orientation
            ))
        )
        let height = max(
            (width * orientation.gridCellHeightOverWidth).rounded(.down), minimumTileSide
        )
        return CGSize(width: width, height: height)
    }

    /// Square tile for Home Recent (Landscape + Vertical Shows share one grid).
    static func homeRecentTileSize(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> CGSize {
        let width = columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: CGFloat(homeGridColumnCount(
                containerWidth: containerWidth,
                sectionInset: sectionInset,
                spacing: spacing
            ))
        )
        return CGSize(width: width, height: width)
    }

    /// Recent Shows on Home: square tiles (both Display Modes) wrapping down the page.
    private static func showsGridSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat,
        showsFormatFilter: Bool = false
    ) -> NSCollectionLayoutSection {
        let columns = homeGridColumnCount(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )
        let tile = homeRecentTileSize(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(tile.width),
            heightDimension: .absolute(tile.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(tile.height)
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
            bottom: sectionInset + 8, trailing: sectionInset
        )

        section.boundarySupplementaryItems = [
            Self.sectionHeaderItem(showsFormatFilter: showsFormatFilter)
        ]
        return section
    }

    /// Short side of a live-ribbon thumb, as a fraction of a 3-up column.
    private static let slideshowRibbonShortSideScale: CGFloat = 0.72

    /// Ribbon thumb size: short side is a fraction of a 3-up column; long side
    /// follows Display Mode (16:9 Landscape, 9:16 Vertical), matching the Show.
    static func slideshowRibbonThumbSize(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation
    ) -> CGSize {
        let full = columnWidth(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing,
            columns: 3
        )
        let short = max(
            (full * slideshowRibbonShortSideScale).rounded(.down),
            minimumTileSide
        )
        let aspect = orientation.aspectRatio
        let width = max(
            (aspect >= 1 ? short * aspect : short).rounded(.down),
            minimumTileSide
        )
        let height = max(
            (aspect >= 1 ? short : short / aspect).rounded(.down),
            minimumTileSide
        )
        return CGSize(width: width, height: height)
    }

    /// Horizontal slide strip while a Slideshow with Live Ribbon is active.
    private static func slideshowRibbonSection(
        containerWidth: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> NSCollectionLayoutSection {
        let thumb = slideshowRibbonThumbSize(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(thumb.width),
            heightDimension: .absolute(thumb.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(thumb.width),
            heightDimension: .absolute(thumb.height)
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
        // No title row — the live hero already identifies the slideshow.
        return section
    }

    /// Nominal Home section-header height (Recent Shows title); empty-state offset.
    static let sectionHeaderEstimatedHeight: CGFloat = 44
    /// Title + All / Landscape / Vertical chips.
    static let sectionHeaderWithFilterEstimatedHeight: CGFloat = 92

    private static func sectionHeaderItem(
        showsFormatFilter: Bool = false
    ) -> NSCollectionLayoutBoundarySupplementaryItem {
        let height = showsFormatFilter
            ? sectionHeaderWithFilterEstimatedHeight
            : sectionHeaderEstimatedHeight
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(height)
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
        let columns = homeGridColumnCount(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )
        let tile = homeTileSize(
            containerWidth: containerWidth,
            sectionInset: sectionInset,
            spacing: spacing
        )

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(tile.width),
            heightDimension: .absolute(tile.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(tile.height)
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
            top: 8, leading: sectionInset,
            bottom: sectionInset, trailing: sectionInset
        )
        return section
    }
}
