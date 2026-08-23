//
//  LiveHeroMiniSlotTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import CoreGraphics
@testable import EclipseiPhone

struct LiveHeroMiniSlotTests {

    @Test func landscapeMiniSitsTopTrailing() {
        let hero = CGRect(x: 16, y: 60, width: 361, height: 203)
        let rect = LiveHeroMiniSlot.targetRect(
            viewSize: CGSize(width: 393, height: 852),
            safeAreaTop: 59,
            headerInset: 16,
            expandedHero: hero,
            isVerticalMode: false
        )
        #expect(rect?.width == 148)
        #expect(rect?.minX == CGFloat(393 - 16 - 148))
        #expect(rect?.minY == CGFloat(59 + 16))
    }

    @Test func verticalMiniIsNarrower() {
        let hero = CGRect(x: 100, y: 60, width: 157, height: 280)
        let rect = LiveHeroMiniSlot.targetRect(
            viewSize: CGSize(width: 393, height: 852),
            safeAreaTop: 59,
            headerInset: 16,
            expandedHero: hero,
            isVerticalMode: true
        )
        #expect(rect?.width == 84)
        #expect(rect?.width ?? 0 < hero.width)
    }

    @Test func skipsWhenHeroIsAlreadyMiniSized() {
        let hero = CGRect(x: 200, y: 60, width: 148, height: 83)
        let rect = LiveHeroMiniSlot.targetRect(
            viewSize: CGSize(width: 393, height: 852),
            safeAreaTop: 59,
            headerInset: 16,
            expandedHero: hero,
            isVerticalMode: false
        )
        #expect(rect == nil)
    }
}
