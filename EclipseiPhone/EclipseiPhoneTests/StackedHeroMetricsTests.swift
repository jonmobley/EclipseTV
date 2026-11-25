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

    @Test func phoneLandscapePaneIsWideAndShortOnly() {
        #expect(StackedHeroMetrics.isPhoneLandscapePane(width: 780, height: 390))
        #expect(StackedHeroMetrics.isPhoneLandscapePane(width: 956, height: 440))
        #expect(!StackedHeroMetrics.isPhoneLandscapePane(width: 390, height: 844))
        #expect(!StackedHeroMetrics.isPhoneLandscapePane(width: 1366, height: 1024))
        // Mid-rotation frames are not landscape yet.
        #expect(!StackedHeroMetrics.isPhoneLandscapePane(width: 500, height: 480))
    }

    @Test func stackedCardTakesTheOutputShape() {
        let bleed: CGFloat = 361   // a 393pt phone inside 16pt insets
        let cap = StackedHeroMetrics.phoneMaxHeight

        // 16:9 fills the width, as it always has.
        let tv = StackedHeroMetrics.stackedSize(bleedWidth: bleed, maxHeight: cap, aspect: 16.0 / 9.0)
        #expect(tv.isFullBleed)
        #expect(abs(tv.size.height - bleed * 9 / 16) < 0.01)

        // 9:16 is capped and centred, as Vertical always has been.
        let vertical = StackedHeroMetrics.stackedSize(bleedWidth: bleed, maxHeight: cap, aspect: 9.0 / 16.0)
        #expect(!vertical.isFullBleed)
        #expect(vertical.size == CGSize(width: 157, height: cap))

        // A five-panel LED wall (2560×768) is a short full-width banner.
        let wideWall = StackedHeroMetrics.stackedSize(bleedWidth: bleed, maxHeight: cap, aspect: 2560.0 / 768.0)
        #expect(wideWall.isFullBleed)
        #expect(wideWall.size.width == bleed)
        #expect(abs(wideWall.size.height - 108.3) < 0.1)

        // A one-panel wall (512×768) is capped like Vertical, in its own shape.
        let tallWall = StackedHeroMetrics.stackedSize(bleedWidth: bleed, maxHeight: cap, aspect: 512.0 / 768.0)
        #expect(!tallWall.isFullBleed)
        #expect(tallWall.size == CGSize(width: 186, height: cap))

        // A capped card never spills past the pane, whatever the shape.
        for aspect: CGFloat in [0.3, 0.667, 1, 1.29, 1.778, 3.33, 6] {
            let card = StackedHeroMetrics.stackedSize(bleedWidth: bleed, maxHeight: cap, aspect: aspect)
            #expect(card.size.width <= bleed)
            #expect(card.size.height <= cap + 1)
            #expect(abs(card.size.width / card.size.height - aspect) / aspect < 0.01)
        }
    }

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
