//
//  HomeLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Covers the tile-sizing floor added in the audit. `NSCollectionLayoutDimension
//  .absolute` traps on a non-positive value, and the container width is briefly zero
//  during early layout (and can be tiny in a narrow split-view column), so the
//  subtraction that derives a tile edge went negative and took the app down.
//
//  Also pins the Home section order: hero, then Recent. An open Show uses a
//  single shows grid (tools + media), with an optional live slideshow ribbon.
//  Home and Show are separate pages — Show sections never include the hero.
//  Phone landscape docks that ribbon under the leading preview instead.
//
//  Open-Show tiles follow Display Mode aspect; Home Recent tiles are square so
//  Landscape and Vertical Shows can share one grid. Live slideshow ribbon
//  thumbs use the same 16:9 / 9:16 stage ratio (not square).
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct HomeLayoutTests {

    private let inset: CGFloat = 16
    /// Matches `LibraryGridViewController.interitemSpacing`.
    private let spacing: CGFloat = 12

    /// Widths the layout can actually be handed, including the degenerate ones that
    /// only appear for a frame during setup.
    private static let widths: [CGFloat] = [
        -320, -1, 0, 1, 8, 32, 40, 100, 320, 390, 430, 744, 1024, 1366
    ]

    @Test func tileStaysPositiveAtEveryContainerWidth() {
        for orientation in ExternalOutputOrientation.allCases {
            for width in Self.widths {
                let tile = LibraryGridViewController.homeTileSize(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                #expect(
                    tile.width > 0 && tile.height > 0,
                    "homeTileSize gave \(tile) for \(orientation) at width \(width)"
                )
            }
        }
    }

    /// An open-Show tile is a miniature of the TV: Vertical tall, Landscape wide.
    @Test func tileShapeFollowsTheDisplayMode() {
        for width in [CGFloat(320), 390, 430, 744, 1024, 1366] {
            let vertical = LibraryGridViewController.homeTileSize(
                containerWidth: width, sectionInset: inset, spacing: spacing,
                orientation: .portrait
            )
            let landscape = LibraryGridViewController.homeTileSize(
                containerWidth: width, sectionInset: inset, spacing: spacing,
                orientation: .landscape
            )

            #expect(vertical.height > vertical.width, "Vertical tile \(vertical) is not tall")
            #expect(landscape.width > landscape.height, "Landscape tile \(landscape) is not wide")
        }
    }

    /// Home Recent mixes both modes, so tiles stay square.
    @Test func homeRecentTilesAreSquare() {
        for width in [CGFloat(320), 390, 430, 744, 1024, 1366] {
            let tile = LibraryGridViewController.homeRecentTileSize(
                containerWidth: width, sectionInset: inset, spacing: spacing
            )
            #expect(tile.width == tile.height, "Recent tile \(tile) is not square")
            #expect(tile.width > 0)
        }
    }

    /// The Home marketing card is 16:9 at every pane size.
    @Test func homeHeroCardIsAlwaysSixteenByNine() {
        for width in [CGFloat(320), 390, 430, 744, 1024, 1366] {
            for height in [CGFloat(844), 1024, 1366] {
                for sizeClass in [UIUserInterfaceSizeClass.compact, .regular] {
                    let card = HomeHeroCarouselCell.cardSize(
                        availableWidth: width - inset * 2,
                        containerHeight: height,
                        horizontalSizeClass: sizeClass
                    )
                    #expect(card.width > 0 && card.height > 0)
                    #expect(
                        abs(card.width / card.height - 16.0 / 9.0) < 0.02,
                        "hero \(card) is not 16:9 at \(width)×\(height) \(sizeClass.rawValue)"
                    )
                }
            }
        }
    }

    @Test func homeHeroSpansThePhonePortraitPane() {
        let available: CGFloat = 390 - inset * 2
        let card = HomeHeroCarouselCell.cardSize(
            availableWidth: available,
            containerHeight: 844,
            horizontalSizeClass: .compact
        )
        #expect(abs(card.width - available) < 2)
    }

    @Test func homeHeroDoesNotSpanThirteenInchLandscape() {
        let available: CGFloat = 1366 - inset * 2
        let card = HomeHeroCarouselCell.cardSize(
            availableWidth: available,
            containerHeight: 1024,
            horizontalSizeClass: .regular
        )
        #expect(card.width < available - 40)
        #expect(abs(card.width / card.height - 16.0 / 9.0) < 0.02)
    }

    @Test func columnCountNeverFallsBelowTheModeBaseline() {
        for orientation in ExternalOutputOrientation.allCases {
            for width in Self.widths {
                let columns = LibraryGridViewController.homeGridColumnCount(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                #expect(
                    CGFloat(columns) >= orientation.gridColumnCount,
                    "got \(columns) columns for \(orientation) at width \(width)"
                )
            }
        }
    }

    @Test func widerPanesGainColumnsUpToFour() {
        for orientation in ExternalOutputOrientation.allCases {
            let phone = LibraryGridViewController.homeGridColumnCount(
                containerWidth: 390, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            let tablet = LibraryGridViewController.homeGridColumnCount(
                containerWidth: 1024, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )

            #expect(CGFloat(phone) == orientation.gridColumnCount)
            #expect(tablet > phone)
            #expect(tablet <= ExternalOutputOrientation.maxGridColumnCount)
        }
    }

    /// 13-inch landscape keeps four columns so leftover width grows the tile.
    @Test func largestIPadGrowsTilesInsteadOfAddingColumns() {
        for orientation in ExternalOutputOrientation.allCases {
            let mid = LibraryGridViewController.homeGridColumnCount(
                containerWidth: 1024, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            let largest = LibraryGridViewController.homeGridColumnCount(
                containerWidth: 1366, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            #expect(mid == ExternalOutputOrientation.maxGridColumnCount)
            #expect(largest == ExternalOutputOrientation.maxGridColumnCount)

            let midTile = LibraryGridViewController.homeTileSize(
                containerWidth: 1024, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            let largeTile = LibraryGridViewController.homeTileSize(
                containerWidth: 1366, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            #expect(largeTile.width > midTile.width)
        }
    }

    /// Vertical is 3-up on a portrait phone and 4-up once the pane is landscape-wide.
    @Test func verticalGainsAFourthColumnWhenThePhoneTurns() {
        let portrait = LibraryGridViewController.homeGridColumnCount(
            containerWidth: 402, sectionInset: inset, spacing: spacing,
            orientation: .portrait
        )
        let landscape = LibraryGridViewController.homeGridColumnCount(
            containerWidth: 780, sectionInset: inset, spacing: spacing,
            orientation: .portrait
        )
        #expect(portrait == 3)
        #expect(landscape == 4)

        // A full row still spans the pane — no trailing dead band beside 3 skinny tiles.
        let tile = LibraryGridViewController.homeTileSize(
            containerWidth: 780, sectionInset: inset, spacing: spacing,
            orientation: .portrait
        )
        let used = tile.width * 4 + spacing * 3 + inset * 2
        #expect(used <= 780)
        #expect(780 - used < inset)
    }

    @Test func aRowOfTilesFitsInsideItsContainer() {
        for orientation in ExternalOutputOrientation.allCases {
            for width in [CGFloat(320), 390, 430, 744, 1024, 1366] {
                let columns = CGFloat(LibraryGridViewController.homeGridColumnCount(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                ))
                let tile = LibraryGridViewController.homeTileSize(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                let used = tile.width * columns + spacing * (columns - 1) + inset * 2
                #expect(used <= width, "\(columns) × \(tile.width) overflows a \(width)pt pane")
            }
        }
    }

    /// Absolute tile widths + section insets must leave no large trailing gutter.
    ///
    /// A double-counted inset (sizing against the full width, then insetting again)
    /// left a ~32pt black band on the right of a 3-up Vertical row.
    @Test func verticalRowFillsTheContainerInARealCollectionView() {
        ExternalOutputOrientationFixture.with(.portrait) {
            let width: CGFloat = 390
            let layout = LibraryGridViewController.makeHomeLayout(
                sectionInset: inset,
                spacing: spacing
            ) { .home }

            let collectionView = UICollectionView(
                frame: CGRect(x: 0, y: 0, width: width, height: 844),
                collectionViewLayout: layout
            )
            let dataSource = OverreportingDataSource()
            dataSource.register(on: collectionView)
            // Home is hero (0) + Recent (1); size the Shows grid.
            dataSource.sectionCount = 2
            dataSource.itemsPerSection = 6
            collectionView.dataSource = dataSource
            collectionView.reloadData()
            collectionView.layoutIfNeeded()

            let showsSection = 1
            let frames = (0..<3).compactMap { item -> CGRect? in
                collectionView.layoutAttributesForItem(
                    at: IndexPath(item: item, section: showsSection)
                )?.frame
            }
            #expect(frames.count == 3)

            let trailing = frames.map(\.maxX).max() ?? 0
            let gutter = width - trailing
            // Section trailing inset (16) plus sub-point flooring slack — not a tile gap.
            #expect(
                gutter <= inset + 2,
                "Vertical 3-up left a \(gutter)pt trailing gutter (frames \(frames))"
            )
        }
    }

    @Test func homeLeadsWithHeroThenShows() {
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: false, showsSlideshowRibbon: false
        ) == [.hero, .shows])

        // A live slideshow must not push a ribbon onto Home either.
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: false, showsSlideshowRibbon: true
        ) == [.hero, .shows])
    }

    @Test func openShowUsesShowsGridWithoutInGridRibbon() {
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: true, showsSlideshowRibbon: false
        ) == [.shows])

        // Ribbon chrome docks under the hero; the scrolling Show grid stays [.shows].
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: true, showsSlideshowRibbon: true
        ) == [.slideshowRibbon, .shows])
    }

    /// Live ribbon docks under the hero on both axes, so the Show grid never
    /// owns an in-grid strip.
    @Test func liveRibbonNeverUsesTheInGridSection() {
        #expect(LibraryGridViewController.showsInGridSlideshowRibbon(
            liveRibbon: true, sideBySideChrome: true
        ) == false)
        #expect(LibraryGridViewController.showsInGridSlideshowRibbon(
            liveRibbon: true, sideBySideChrome: false
        ) == false)
        #expect(LibraryGridViewController.showsInGridSlideshowRibbon(
            liveRibbon: false, sideBySideChrome: false
        ) == false)
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: true,
            showsSlideshowRibbon: LibraryGridViewController.showsInGridSlideshowRibbon(
                liveRibbon: true, sideBySideChrome: false
            )
        ) == [.shows])
    }

    /// Live ribbon thumbs match the Show stage: 16:9 Landscape, 9:16 Vertical.
    @Test func slideshowRibbonThumbsFollowTheDisplayMode() {
        for width in [CGFloat(320), 390, 430, 744, 1024, 1366] {
            let vertical = LibraryGridViewController.slideshowRibbonThumbSize(
                containerWidth: width, sectionInset: inset, spacing: spacing,
                orientation: .portrait
            )
            let landscape = LibraryGridViewController.slideshowRibbonThumbSize(
                containerWidth: width, sectionInset: inset, spacing: spacing,
                orientation: .landscape
            )

            #expect(
                vertical.height > vertical.width,
                "Vertical ribbon thumb \(vertical) is not tall"
            )
            #expect(
                landscape.width > landscape.height,
                "Landscape ribbon thumb \(landscape) is not wide"
            )
            // Short sides can differ across modes (Vertical is 3-up, Landscape 2-up
            // on phone); each thumb still keeps the stage aspect of its mode.
            #expect(abs(landscape.width / landscape.height - 16.0 / 9.0) < 0.05)
            #expect(abs(vertical.height / vertical.width - 16.0 / 9.0) < 0.05)
        }
    }

    @Test func slideshowRibbonThumbsStayPositiveAtEveryContainerWidth() {
        for orientation in ExternalOutputOrientation.allCases {
            for width in Self.widths {
                let thumb = LibraryGridViewController.slideshowRibbonThumbSize(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                #expect(
                    thumb.width > 0 && thumb.height > 0,
                    "ribbon thumb \(thumb) for \(orientation) at width \(width)"
                )
            }
        }
    }

    /// Ribbon thumbs stay a fixed fraction of the Show-grid tile at every width.
    @Test func slideshowRibbonThumbsScaleFromTheShowGridTile() {
        let scale = LibraryGridViewController.slideshowRibbonShortSideScale
        for orientation in ExternalOutputOrientation.allCases {
            for width in [CGFloat(390), 1024, 1366] {
                let tile = LibraryGridViewController.homeTileSize(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                let thumb = LibraryGridViewController.slideshowRibbonThumbSize(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                #expect(thumb.width == (tile.width * scale).rounded(.down))
                #expect(thumb.height == (tile.height * scale).rounded(.down))
                #expect(
                    thumb.width < tile.width && thumb.height < tile.height,
                    "ribbon \(thumb) should be smaller than grid tile \(tile)"
                )
            }
        }
    }

    /// The live ribbon section must emit the same size as `slideshowRibbonThumbSize`.
    @Test func slideshowRibbonCellsMatchDisplayModeInARealCollectionView() {
        for orientation in ExternalOutputOrientation.allCases {
            ExternalOutputOrientationFixture.with(orientation) {
                let width: CGFloat = 390
                let layout = LibraryGridViewController.makeHomeLayout(
                    sectionInset: inset,
                    spacing: spacing
                ) {
                    .init(isShowMode: true, showsSlideshowRibbon: true)
                }

                let collectionView = UICollectionView(
                    frame: CGRect(x: 0, y: 0, width: width, height: 844),
                    collectionViewLayout: layout
                )
                let dataSource = OverreportingDataSource()
                dataSource.register(on: collectionView)
                dataSource.sectionCount = 2
                dataSource.itemsPerSection = 4
                collectionView.dataSource = dataSource
                collectionView.reloadData()
                collectionView.layoutIfNeeded()

                let frame = collectionView.layoutAttributesForItem(
                    at: IndexPath(item: 0, section: 0)
                )?.frame
                let expected = LibraryGridViewController.slideshowRibbonThumbSize(
                    containerWidth: width, sectionInset: inset, spacing: spacing,
                    orientation: orientation
                )
                #expect(frame?.size == expected, "ribbon cell \(String(describing: frame?.size))")
            }
        }
    }

    /// Going Home must not be able to put the marketing carousel on a Show page.
    @Test func showPageSectionsNeverIncludeTheHomeHero() {
        for ribbon in [false, true] {
            let sections = LibraryGridViewController.visibleHomeSections(
                isShowMode: true, showsSlideshowRibbon: ribbon
            )
            #expect(!sections.contains(.hero))
        }
    }

    /// The layout must survive a data source that reports sections it can't name.
    ///
    /// Returning nil from the section provider is a hard UIKit assertion, not a
    /// skipped section, so this used to terminate the app rather than fail a check.
    /// A crash here takes the whole test process down — that is the regression.
    @Test func aSectionTheLayoutCannotNameDoesNotTrap() {
        // Home is three sections; the data source below claims four.
        let layout = LibraryGridViewController.makeHomeLayout(
            sectionInset: inset,
            spacing: spacing
        ) { .home }

        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: layout
        )
        let dataSource = OverreportingDataSource()
        dataSource.sectionCount = 4
        dataSource.register(on: collectionView)
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        #expect(collectionView.numberOfSections == dataSource.sectionCount)
    }
}

/// Reports more sections than the layout knows about — what a stale layout snapshot
/// looked like from UIKit's side.
///
/// Every section carries items on purpose. UIKit tolerates a nil section definition
/// for an empty section and only raises on one it has content to render, so an
/// item-less stub would pass against the bug it is meant to catch.
@MainActor
private final class OverreportingDataSource: NSObject, UICollectionViewDataSource {

    var sectionCount = 3
    var itemsPerSection = 3

    private static let cellId = "cell"
    private static let headerId = "header"

    func register(on collectionView: UICollectionView) {
        collectionView.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: Self.cellId
        )
        collectionView.register(
            UICollectionReusableView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: Self.headerId
        )
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sectionCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemsPerSection
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.cellId,
            for: indexPath
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: Self.headerId,
            for: indexPath
        )
    }
}
