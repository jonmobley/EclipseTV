//
//  OverlayAdjustSessionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Dragging and pinching a live overlay on the hero: what gets saved.
//

import CoreGraphics
import Foundation
import Testing
@testable import EclipseiPhone

struct OverlayAdjustSessionTests {

    /// A 16:9 program frame in hero points.
    private let content = CGRect(x: 0, y: 0, width: 320, height: 180)

    private func card(placement: OverlayCardPlacement? = nil,
                      corner: OverlayCorner = .bottomLeading) -> RenderedOverlay {
        .card(ShowTemplateCard(
            showId: UUID(),
            config: OverlayCardConfig(template: .lowerThird, fields: ["name": "Ada"],
                                      corner: corner, placement: placement)
        ))
    }

    private func media(centerX: Double = 0.5, centerY: Double = 0.5,
                       scale: Double = 0.35) -> RenderedOverlay {
        .media(MediaOverlayEntry(itemId: "logo", isVideo: false, centerX: centerX,
                                 centerY: centerY, scale: scale, stackOrder: 0))
    }

    private func placement(_ overlay: RenderedOverlay) -> OverlayCardPlacement? {
        if case .card(let card) = overlay { return card.config.placement }
        return nil
    }

    private func entry(_ overlay: RenderedOverlay) -> MediaOverlayEntry? {
        if case .media(let entry) = overlay { return entry }
        return nil
    }

    // MARK: - Cards

    @Test func touchingADockedCardWithoutMovingKeepsItsCorner() throws {
        let overlay = card()
        let session = try #require(OverlayAdjustSession(
            overlay: overlay, frame: CGRect(x: 8, y: 140, width: 100, height: 30),
            contentFrame: content
        ))
        #expect(session.overlay == overlay)
        #expect(!session.hasChanged)
    }

    @Test func draggingADockedCardGivesItAFreePlacement() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: card(), frame: CGRect(x: 8, y: 140, width: 100, height: 30),
            contentFrame: content
        ))
        session.move(by: CGPoint(x: 40, y: -40))
        let result = try #require(placement(session.overlay))
        #expect(abs(result.centerX - (58 + 40) / 320) < 0.0001)
        #expect(abs(result.centerY - (155 - 40) / 180) < 0.0001)
        #expect(result.scale == 1)
    }

    @Test func pinchingACardScalesFromItsSavedScale() throws {
        let start = OverlayCardPlacement(centerX: 0.5, centerY: 0.5, scale: 1.5)
        var session = try #require(OverlayAdjustSession(
            overlay: card(placement: start),
            frame: CGRect(x: 85, y: 67.5, width: 150, height: 45), contentFrame: content
        ))
        session.scale(by: 0.5)
        let result = try #require(placement(session.overlay))
        #expect(abs(result.scale - 0.75) < 0.0001)
        #expect(abs(session.size.width - 75) < 0.0001)
    }

    @Test func cardScaleStaysInTheMacsRange() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: card(placement: .init(centerX: 0.5, centerY: 0.5, scale: 1)),
            frame: CGRect(x: 150, y: 85, width: 20, height: 10), contentFrame: content
        ))
        session.scale(by: 100)
        #expect(placement(session.overlay)?.scale == OverlayCardPlacement.maxScale)
        session.scale(by: 0.0001)
        #expect(placement(session.overlay)?.scale == OverlayCardPlacement.minScale)
    }

    @Test func cardStaysInsideTheFrame() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: card(), frame: CGRect(x: 8, y: 140, width: 100, height: 30),
            contentFrame: content
        ))
        session.move(by: CGPoint(x: -500, y: 500))
        #expect(session.center == CGPoint(x: 50, y: 165))
    }

    // MARK: - Snap

    @Test func dragSnapsOntoTheCenterlines() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: card(), frame: CGRect(x: 8, y: 140, width: 100, height: 30),
            contentFrame: content
        ))
        session.move(by: CGPoint(x: 160 - 58 + 5, y: 90 - 155 - 6))
        let ticked = session.refreshSnap()
        #expect(ticked)
        #expect(session.center == CGPoint(x: 160, y: 90))
        #expect(session.snap == OverlayAdjustSnap(vertical: true, horizontal: true))
        // Staying on the lines does not tick again.
        session.move(by: CGPoint(x: 1, y: 0))
        let tickedAgain = session.refreshSnap()
        #expect(!tickedAgain)
    }

    // MARK: - Media

    @Test func draggingMediaMovesItsCenter() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: media(), frame: CGRect(x: 104, y: 58.5, width: 112, height: 63),
            contentFrame: content
        ))
        session.move(by: CGPoint(x: 64, y: 36))
        let result = try #require(entry(session.overlay))
        #expect(abs(result.centerX - 0.7) < 0.0001)
        #expect(abs(result.centerY - 0.7) < 0.0001)
        #expect(result.scale == 0.35)
    }

    @Test func pinchingMediaChangesItsWidthWithinRange() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: media(), frame: CGRect(x: 104, y: 58.5, width: 112, height: 63),
            contentFrame: content
        ))
        session.scale(by: 2)
        #expect(abs((entry(session.overlay)?.scale ?? 0) - 0.7) < 0.0001)
        session.scale(by: 10)
        #expect(entry(session.overlay)?.scale == MediaOverlayEntry.scaleRange.upperBound)
    }

    @Test func mediaMayHangOffAnEdgeLikeOnTheMac() throws {
        var session = try #require(OverlayAdjustSession(
            overlay: media(), frame: CGRect(x: 104, y: 58.5, width: 112, height: 63),
            contentFrame: content
        ))
        session.move(by: CGPoint(x: 150, y: 0))
        #expect(session.center == CGPoint(x: 310, y: 90))
        session.move(by: CGPoint(x: 500, y: -500))
        let result = try #require(entry(session.overlay))
        #expect(result.centerX == 1)
        #expect(result.centerY == 0)
    }

    @Test func emptyFramesStartNothing() {
        #expect(OverlayAdjustSession(overlay: media(), frame: .zero, contentFrame: content) == nil)
        #expect(OverlayAdjustSession(
            overlay: media(), frame: CGRect(x: 0, y: 0, width: 10, height: 10), contentFrame: .zero
        ) == nil)
    }
}
