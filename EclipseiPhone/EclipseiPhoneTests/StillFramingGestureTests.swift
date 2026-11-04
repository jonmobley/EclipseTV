//
//  StillFramingGestureTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Pinch / drag math for adjusting a still directly on the live preview.
struct StillFramingGestureTests {

    private let aspect = MediaAspect.landscape
    /// A 4:3 photo on a 16:9 panel, so Fit and Fill differ.
    private let photo = CGSize(width: 1200, height: 900)

    private var fill: CGRect { MediaCropGeometry.fillRect(in: photo, aspect: aspect) }
    private var fit: CGRect { MediaCropGeometry.fitRect(in: photo, aspect: aspect) }

    // MARK: - startRect

    @Test func startsFromFillOrFitWithoutFraming() {
        let fromFill = StillFramingGesture.startRect(
            imageSize: photo, framing: nil, mode: .fill, aspect: aspect
        )
        let fromFit = StillFramingGesture.startRect(
            imageSize: photo, framing: nil, mode: .fit, aspect: aspect
        )
        #expect(fromFill == fill)
        #expect(fromFit == fit)
    }

    @Test func startsFromSavedFraming() {
        let saved = MediaFraming(
            rect: CGRect(x: 100, y: 100, width: 480, height: 270), in: photo
        )
        let start = StillFramingGesture.startRect(
            imageSize: photo, framing: saved, mode: .fit, aspect: aspect
        )
        #expect(abs(start.width - 480) < 0.5)
        #expect(abs(start.minX - 100) < 0.5)
    }

    // MARK: - zoomed

    @Test func pinchingInShrinksTheRegionAboutTheAnchor() {
        let zoomed = StillFramingGesture.zoomed(
            fill, by: 2, anchor: CGPoint(x: 0.5, y: 0.5), imageSize: photo
        )
        #expect(abs(zoomed.width - fill.width / 2) < 0.5)
        #expect(abs(zoomed.midX - fill.midX) < 0.5)
        #expect(abs(zoomed.midY - fill.midY) < 0.5)
    }

    @Test func pinchingInKeepsTheCornerUnderTheFingers() {
        let zoomed = StillFramingGesture.zoomed(
            fill, by: 2, anchor: CGPoint(x: 0, y: 0), imageSize: photo
        )
        #expect(abs(zoomed.minX - fill.minX) < 0.5)
        #expect(abs(zoomed.minY - fill.minY) < 0.5)
    }

    @Test func pinchingOutStopsAtFit() {
        let zoomed = StillFramingGesture.zoomed(
            fill, by: 0.1, anchor: CGPoint(x: 0.5, y: 0.5), imageSize: photo
        )
        #expect(abs(zoomed.width - fit.width) < 0.5)
    }

    @Test func zoomHasALimit() {
        let zoomed = StillFramingGesture.zoomed(
            fill, by: 1000, anchor: CGPoint(x: 0.5, y: 0.5), imageSize: photo
        )
        #expect(abs(zoomed.width - fill.width / StillFramingGesture.maxZoom) < 0.5)
    }

    @Test func zoomKeepsTheDisplayAspect() {
        let zoomed = StillFramingGesture.zoomed(
            fill, by: 3, anchor: CGPoint(x: 0.2, y: 0.7), imageSize: photo
        )
        #expect(abs(zoomed.width / zoomed.height - aspect) < 0.01)
    }

    // MARK: - panned

    @Test func draggingRightShowsMoreOfTheLeft() {
        let region = StillFramingGesture.zoomed(
            fill, by: 2, anchor: CGPoint(x: 0.5, y: 0.5), imageSize: photo
        )
        let view = CGSize(width: 320, height: 180)
        let moved = StillFramingGesture.panned(
            region, by: CGPoint(x: 32, y: 0), viewSize: view, imageSize: photo
        )
        // 32 of 320 preview points is a tenth of the region's width.
        #expect(abs(moved.minX - (region.minX - region.width / 10)) < 0.5)
        #expect(moved.minY == region.minY)
    }

    @Test func draggingNeverPullsThePhotoOffScreen() {
        let region = StillFramingGesture.zoomed(
            fill, by: 2, anchor: CGPoint(x: 0.5, y: 0.5), imageSize: photo
        )
        let moved = StillFramingGesture.panned(
            region,
            by: CGPoint(x: 10_000, y: 10_000),
            viewSize: CGSize(width: 320, height: 180),
            imageSize: photo
        )
        #expect(moved.minX >= -0.5)
        #expect(moved.minY >= -0.5)
    }

    // MARK: - outcome

    @Test func endingAtFillOrFitSnapsBackToThatMode() {
        #expect(StillFramingGesture.outcome(
            for: fill, imageSize: photo, currentMode: .fit
        ) == .mode(.fill))
        #expect(StillFramingGesture.outcome(
            for: fit, imageSize: photo, currentMode: .fill
        ) == .mode(.fit))
    }

    @Test func endingNearFillSnaps() {
        let nearly = fill.insetBy(dx: fill.width * 0.005, dy: fill.height * 0.005)
        #expect(StillFramingGesture.outcome(
            for: nearly, imageSize: photo, currentMode: .fit
        ) == .mode(.fill))
    }

    @Test func endingZoomedInSavesACustomPosition() {
        let region = StillFramingGesture.zoomed(
            fill, by: 2, anchor: CGPoint(x: 0.5, y: 0.5), imageSize: photo
        )
        guard case .custom(let framing) = StillFramingGesture.outcome(
            for: region, imageSize: photo, currentMode: .fill
        ) else {
            Issue.record("Expected a custom framing")
            return
        }
        #expect(abs(framing.width - region.width / photo.width) < 0.001)
    }

    @Test func fillSizedButMovedIsCustom() {
        // A panel-tall crop slid to one side is a real choice, not plain Fill.
        let shifted = MediaCropGeometry.placed(
            fill.offsetBy(dx: 0, dy: -200), in: photo
        ) ?? fill
        guard case .custom = StillFramingGesture.outcome(
            for: shifted, imageSize: photo, currentMode: .fill
        ) else {
            Issue.record("Expected a custom framing")
            return
        }
    }

    @Test func panelShapedStillKeepsItsMode() {
        let panelShaped = CGSize(width: 1600, height: 900)
        let rect = MediaCropGeometry.fillRect(in: panelShaped, aspect: aspect)
        #expect(StillFramingGesture.outcome(
            for: rect, imageSize: panelShaped, currentMode: .fit
        ) == .mode(.fit))
    }
}
