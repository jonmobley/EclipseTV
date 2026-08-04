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
//
//  Open-Show tiles follow Display Mode aspect; Home Recent tiles are square so
//  Landscape and Vertical Shows can share one grid.
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

    @Test func widerPanesGainColumnsRatherThanBiggerTiles() {
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

            // The point of adding columns is that the tile itself stops growing.
            let phoneTile = LibraryGridViewController.homeTileSize(
                containerWidth: 390, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            let tabletTile = LibraryGridViewController.homeTileSize(
                containerWidth: 1024, sectionInset: inset, spacing: spacing,
                orientation: orientation
            )
            #expect(tabletTile.width < phoneTile.width * 2)
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
        let previous = ExternalOutputSettings.orientation
        ExternalOutputSettings.orientation = .portrait
        defer { ExternalOutputSettings.orientation = previous }

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

    @Test func homeLeadsWithHeroThenShows() {
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: false, showsSlideshowRibbon: false
        ) == [.hero, .shows])

        // A live slideshow must not push a ribbon onto Home either.
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: false, showsSlideshowRibbon: true
        ) == [.hero, .shows])
    }

    @Test func openShowUsesShowsGridAndAddsTheRibbonWhenLive() {
        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: true, showsSlideshowRibbon: false
        ) == [.shows])

        #expect(LibraryGridViewController.visibleHomeSections(
            isShowMode: true, showsSlideshowRibbon: true
        ) == [.slideshowRibbon, .shows])
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
