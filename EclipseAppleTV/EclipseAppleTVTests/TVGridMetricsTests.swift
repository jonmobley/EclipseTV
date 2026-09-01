//
//  TVGridMetricsTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import CoreGraphics
@testable import EclipseAppleTV

struct TVGridMetricsTests {

    @Test func landscapeAspectIsSixteenByNine() {
        let ratio = TVGridMetrics.cellHeightOverWidth(for: .landscape)
        #expect(abs(ratio - 9.0 / 16.0) < 0.0001)
        #expect(TVGridMetrics.columnCount(for: .landscape) == 3)
    }

    @Test func verticalAspectIsNineBySixteen() {
        let ratio = TVGridMetrics.cellHeightOverWidth(for: .vertical)
        #expect(abs(ratio - 16.0 / 9.0) < 0.0001)
        #expect(TVGridMetrics.columnCount(for: .vertical) == 5)
    }

    @Test func thumbnailTargetsMatchMode() {
        #expect(
            TVGridMetrics.thumbnailTargetSize(for: .landscape)
                == CGSize(width: 480, height: 270)
        )
        #expect(
            TVGridMetrics.thumbnailTargetSize(for: .vertical)
                == CGSize(width: 270, height: 480)
        )
    }

    @Test func itemSizeFloorsAtMinimumWhenWidthIsZero() {
        let size = TVGridMetrics.itemSize(collectionWidth: 0, mode: .landscape)
        #expect(size.width >= TVGridMetrics.minimumTileSide)
        #expect(size.height >= TVGridMetrics.minimumTileSide)
    }

    @Test func itemSizeUsesModeAspectOnWideScreen() {
        let landscape = TVGridMetrics.itemSize(collectionWidth: 1920, mode: .landscape)
        let vertical = TVGridMetrics.itemSize(collectionWidth: 1920, mode: .vertical)
        #expect(landscape.width > landscape.height)
        #expect(vertical.height > vertical.width)
        #expect(vertical.width < landscape.width)
    }
}
