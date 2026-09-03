//
//  StackedHeroMetricsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct StackedHeroMetricsTests {

    private let inset: CGFloat = 16
    private let zeroSafe = UIEdgeInsets.zero

    @Test func compactWidthStaysAtThePhoneCap() {
        for aspect in [16.0 / 9.0, 9.0 / 16.0] {
            let height = StackedHeroMetrics.maxHeight(
                containerSize: CGSize(width: 390, height: 844),
                horizontalSizeClass: .compact,
                headerInset: inset,
                safeAreaInsets: zeroSafe,
                aspectWidthOverHeight: aspect
            )
            #expect(height == StackedHeroMetrics.phoneMaxHeight)
        }
    }

    @Test func thirteenInchLandscapePreviewGrowsPastThePhoneCap() {
        let height = StackedHeroMetrics.maxHeight(
            containerSize: CGSize(width: 1366, height: 1024),
            horizontalSizeClass: .regular,
            headerInset: inset,
            safeAreaInsets: zeroSafe,
            aspectWidthOverHeight: 16.0 / 9.0
        )
        #expect(height > StackedHeroMetrics.phoneMaxHeight)
        // Not full-bleed 16:9 — that would swallow the grid (~750pt).
        let bleed = (1366 - inset * 2) * 9.0 / 16.0
        #expect(height < bleed)
    }

    @Test func thirteenInchPortraitLandscapeUsesNearlyFullBleed() {
        let height = StackedHeroMetrics.maxHeight(
            containerSize: CGSize(width: 1024, height: 1366),
            horizontalSizeClass: .regular,
            headerInset: inset,
            safeAreaInsets: zeroSafe,
            aspectWidthOverHeight: 16.0 / 9.0
        )
        let bleed = (1024 - inset * 2) * 9.0 / 16.0
        #expect(abs(height - bleed) < 2)
    }

    @Test func thirteenInchVerticalPreviewGrowsPastThePhoneCap() {
        let height = StackedHeroMetrics.maxHeight(
            containerSize: CGSize(width: 1366, height: 1024),
            horizontalSizeClass: .regular,
            headerInset: inset,
            safeAreaInsets: zeroSafe,
            aspectWidthOverHeight: 9.0 / 16.0
        )
        #expect(height > StackedHeroMetrics.phoneMaxHeight)
        let width = height * 9.0 / 16.0
        #expect(width < 1366 - inset * 2)
    }
}
