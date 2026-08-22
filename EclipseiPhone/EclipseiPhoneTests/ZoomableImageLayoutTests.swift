//
//  ZoomableImageLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct ZoomableImageLayoutTests {

    @Test func containUsesTheSmallerAxis() {
        let scale = ZoomableImageLayout.minimumScale(
            imageSize: CGSize(width: 4000, height: 3000),
            boundsSize: CGSize(width: 400, height: 800),
            fit: .contain
        )
        #expect(scale == 0.1)
    }

    @Test func coverUsesTheLargerAxis() {
        let scale = ZoomableImageLayout.minimumScale(
            imageSize: CGSize(width: 4000, height: 3000),
            boundsSize: CGSize(width: 400, height: 800),
            fit: .cover
        )
        #expect(abs(scale - (800.0 / 3000.0)) < 0.0001)
    }

    @Test func emptySizesReturnOne() {
        let emptyImage = ZoomableImageLayout.minimumScale(
            imageSize: .zero,
            boundsSize: CGSize(width: 100, height: 100),
            fit: .contain
        )
        let emptyBounds = ZoomableImageLayout.minimumScale(
            imageSize: CGSize(width: 100, height: 100),
            boundsSize: .zero,
            fit: .cover
        )
        #expect(emptyImage == 1)
        #expect(emptyBounds == 1)
    }

    @Test func maxZoomIsFourTimesFit() {
        #expect(ZoomableImageLayout.maxZoomMultiplier == 4)
    }
}
