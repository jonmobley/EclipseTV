//
//  LibraryThumbnailCellLiveStrokeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// `setLive` owns the card border outright.
///
/// The Show grid reconciles the red live stroke across every visible tile after a
/// reload, which means it clears strokes on cells it did not configure. That only
/// works if clearing restores the edge the tile registered for its idle state —
/// the Camera hairline, a select-mode check ring — instead of erasing it.
@MainActor
struct LibraryThumbnailCellLiveStrokeTests {

    @Test func goingLiveDrawsTheRedStroke() {
        let cell = makeCell()
        cell.setLive(true)
        #expect(cell.cardView.layer.borderWidth == 3)
        #expect(cell.cardView.layer.borderColor == UIColor.systemRed.cgColor)
    }

    @Test func lockedLiveDrawsAmberInstead() {
        let cell = makeCell()
        cell.setLive(true, isLocked: true)
        #expect(cell.cardView.layer.borderColor == UIColor.systemOrange.cgColor)
    }

    @Test func clearingAStrokeRestoresTheIdleEdgeRatherThanErasingIt() {
        let cell = makeCell()
        let hairline = UIColor.white.withAlphaComponent(0.3)
        cell.setIdleBorder(width: 1, color: hairline)
        cell.setLive(true)
        #expect(cell.cardView.layer.borderWidth == 3)

        cell.setLive(false)
        #expect(cell.cardView.layer.borderWidth == 1)
        #expect(cell.cardView.layer.borderColor == hairline.cgColor)
    }

    /// Registering an idle edge under a live tile must not steal the stroke: the
    /// Camera tile registers its hairline on every configure pass, live or not.
    @Test func registeringAnIdleEdgeWhileLiveLeavesTheStrokeAlone() {
        let cell = makeCell()
        cell.setLive(true)
        cell.setIdleBorder(width: 1, color: .separator)
        #expect(cell.cardView.layer.borderWidth == 3)
        #expect(cell.cardView.layer.borderColor == UIColor.systemRed.cgColor)

        cell.setLive(false)
        #expect(cell.cardView.layer.borderWidth == 1)
    }

    @Test func aTileWithNoIdleEdgeGoesBackToNoBorder() {
        let cell = makeCell()
        cell.setLive(true)
        cell.setLive(false)
        #expect(cell.cardView.layer.borderWidth == 0)
    }

    @Test func resetChromeDropsTheIdleEdgeWithTheRestOfTheChrome() {
        let cell = makeCell()
        cell.setIdleBorder(width: 1, color: .separator)
        cell.resetChrome()
        #expect(cell.cardView.layer.borderWidth == 0)

        cell.setLive(false)
        #expect(cell.cardView.layer.borderWidth == 0)
    }

    /// A checked tile in select mode is never live, so reconciliation clears it —
    /// and the check ring has to survive that.
    @Test func aCheckedTileKeepsItsRingThroughReconciliation() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Runsheet",
            systemImage: "doc.richtext",
            thumbnail: nil,
            fillColor: .specialTile,
            isLive: false
        )
        cell.setShowSelectMode(enabled: true, isSelected: true, isSelectable: true)
        #expect(cell.cardView.layer.borderColor == UIColor.accent.cgColor)

        cell.setLive(false)
        #expect(cell.cardView.layer.borderWidth == 3)
        #expect(cell.cardView.layer.borderColor == UIColor.accent.cgColor)
    }

    @Test func theCameraTileKeepsItsHairlineWhenItStopsBeingLive() {
        let cell = makeCell()
        cell.configureCamera(isLive: true, lastFrame: nil, warmPreview: false)
        #expect(cell.cardView.layer.borderWidth == 3)

        cell.configureCamera(isLive: false, lastFrame: nil, warmPreview: false)
        #expect(cell.cardView.layer.borderWidth == 1)
    }

    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }
}
