//
//  CameraStackedLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Portrait hold of a Landscape Show: header above the 16:9 panel, Show-style
/// thumbnail grid below it, nothing floating over the camera.
@MainActor
struct CameraStackedLayoutTests {

    private let phone = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let landscape: CGFloat = 16.0 / 9.0

    private var dock: CGFloat {
        CameraLiveViewController.captureDockSpan(safeEdge: 34)
    }

    private var tile: CGSize {
        CameraLiveViewController.thumbGridTileSize(width: phone.width, orientation: .landscape)
    }

    @Test func gridTilesMatchAnOpenShowsGrid() {
        let show = LibraryGridViewController.homeTileSize(
            containerWidth: phone.width,
            sectionInset: 16,
            spacing: 12,
            orientation: .landscape
        )
        #expect(tile == show)
        #expect(tile.width == 173)
        #expect(tile.height == 97)
        // Two tiles and the gap fill the width exactly between the 16pt insets.
        #expect(tile.width * 2 + 12 == phone.width - 32)
    }

    @Test func stackedLayoutPutsHeaderAbovePanelAndGridBelow() throws {
        let layout = try #require(
            CameraLiveViewController.stackedLayout(
                in: phone,
                safeTop: 59,
                aspect: landscape,
                dockSpan: dock,
                tileHeight: tile.height
            )
        )
        #expect(layout.header.minY == 59 + 8)
        #expect(layout.header.height == CameraLiveViewController.chromeControlSize)
        #expect(layout.panel.minY == layout.header.maxY + CameraLiveViewController.stackedHeaderGap)
        #expect(layout.panel.width == phone.width)
        #expect(abs(layout.panel.width / layout.panel.height - landscape) < 0.02)
        let gridInset = CameraLiveViewController.thumbGridSectionInset
        #expect(layout.grid.minY == layout.panel.maxY + gridInset)
        #expect(layout.grid.maxY == phone.height - dock)
        #expect(layout.grid.width == phone.width)
    }

    @Test func stackedGridFitsThreeRowsOnAStandardPhone() throws {
        let layout = try #require(
            CameraLiveViewController.stackedLayout(
                in: phone,
                safeTop: 59,
                aspect: landscape,
                dockSpan: dock,
                tileHeight: tile.height
            )
        )
        let rows: CGFloat = 3
        let needed = rows * tile.height + (rows - 1) * 12 + 16
        #expect(layout.grid.height >= needed)
    }

    @Test func verticalShowDoesNotStack() {
        #expect(
            CameraLiveViewController.stackedLayout(
                in: phone,
                safeTop: 59,
                aspect: 9.0 / 16.0,
                dockSpan: dock,
                tileHeight: tile.height
            ) == nil
        )
    }

    /// No band tall enough for a tile row means the centered overlay is better.
    @Test func stackingNeedsRoomForAtLeastOneTileRow() {
        let short = CGRect(x: 0, y: 0, width: 390, height: 460)
        #expect(
            CameraLiveViewController.stackedLayout(
                in: short,
                safeTop: 59,
                aspect: landscape,
                dockSpan: dock,
                tileHeight: tile.height
            ) == nil
        )
    }

    @Test func gridOrderMirrorsTheRibbonsProgramFramesThenStills() {
        let frameA = UUID()
        let frameB = UUID()
        let cutaway = UUID()
        let items = CameraLiveViewController.thumbGridItems(
            showsProgram: true,
            frameIds: [frameA, frameB],
            stills: [.background, .cutaway(cutaway), .add]
        )
        #expect(items == [
            .program,
            .frame(frameA),
            .frame(frameB),
            .still(.background),
            .still(.cutaway(cutaway)),
            .still(.add)
        ])
    }

    @Test func gridOmitsProgramWhenNothingIsConnected() {
        let items = CameraLiveViewController.thumbGridItems(
            showsProgram: false,
            frameIds: [],
            stills: [.background, .add]
        )
        #expect(items == [.still(.background), .still(.add)])
    }

    @Test func portraitLandscapeShowStacksHeaderPanelGridDock() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let vc = CameraLiveViewController()
            vc.loadViewIfNeeded()
            vc.view.bounds = phone
            vc.view.layoutIfNeeded()
            vc.refreshLiveChrome()

            let panel = vc.panelView.frame
            #expect(vc.stackedLayout != nil)
            #expect(abs(panel.width / panel.height - landscape) < 0.02)

            // Header clear of the camera.
            #expect(vc.backButton.frame.maxY <= panel.minY)
            #expect(vc.settingsButton.frame.maxY <= panel.minY)
            #expect(vc.goLiveButton.frame.maxY <= panel.minY)

            // Grid between the panel and the dock, ribbons out of the way.
            #expect(vc.thumbGridView.isHidden == false)
            #expect(vc.thumbGridView.frame.minY >= panel.maxY)
            #expect(vc.thumbGridView.frame.maxY <= vc.shutterButton.frame.minY + 0.5)
            #expect(vc.stillRibbonView.isHidden)
            #expect(vc.frameRibbonView.isHidden)
            #expect(vc.liveOutputThumbView.isHidden)

            let layout = vc.thumbGridView.collectionViewLayout as? UICollectionViewFlowLayout
            #expect(layout?.itemSize == tile)
            #expect(layout?.sectionInset.left == 16)
            #expect(layout?.minimumInteritemSpacing == 12)
        }
    }

    @Test func portraitVerticalShowKeepsTheOverlayChrome() {
        ExternalOutputOrientationFixture.with(.portrait) {
            let vc = CameraLiveViewController()
            vc.loadViewIfNeeded()
            vc.view.bounds = phone
            vc.view.layoutIfNeeded()
            vc.refreshLiveChrome()

            #expect(vc.stackedLayout == nil)
            #expect(vc.thumbGridView.isHidden)
            #expect(vc.stillRibbonView.isHidden == false)
            let panel = vc.panelView.frame
            #expect(vc.backButton.frame.minY >= panel.minY)
        }
    }

    @Test func landscapeHoldKeepsTheOverlayChrome() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let vc = CameraLiveViewController()
            vc.loadViewIfNeeded()
            vc.view.bounds = CGRect(x: 0, y: 0, width: 844, height: 390)
            vc.view.layoutIfNeeded()
            vc.refreshLiveChrome()

            #expect(vc.stackedLayout == nil)
            #expect(vc.thumbGridView.isHidden)
        }
    }
}
