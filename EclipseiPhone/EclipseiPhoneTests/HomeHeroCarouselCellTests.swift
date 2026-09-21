//
//  HomeHeroCarouselCellTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct HomeHeroCarouselCellTests {

    @Test func pagingPagesFillTheCardAfterLayout() {
        let cell = HomeHeroCarouselCell(
            frame: CGRect(x: 0, y: 0, width: 390, height: 247)
        )
        cell.reload()
        cell.layoutIfNeeded()
        let scroll = cell.pagingScrollView
        #expect(scroll.bounds.width > 0)
        #expect(scroll.bounds.height > 0)
        let looped = CGFloat(HomeHeroSlide.all.count + 2)
        #expect(
            abs(scroll.contentSize.width - scroll.bounds.width * looped) < 1
        )
    }

    @Test func pagingRelayoutsWhenTheCardGrows() {
        let cell = HomeHeroCarouselCell(
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )
        cell.reload()
        cell.layoutIfNeeded()
        let firstWidth = cell.pagingScrollView.contentSize.width
        cell.frame = CGRect(x: 0, y: 0, width: 800, height: 480)
        cell.reload()
        cell.layoutIfNeeded()
        #expect(cell.pagingScrollView.contentSize.width > firstWidth)
        let looped = CGFloat(HomeHeroSlide.all.count + 2)
        #expect(
            abs(
                cell.pagingScrollView.contentSize.width
                    - cell.pagingScrollView.bounds.width * looped
            ) < 1
        )
    }

    /// Landscape cells are shorter than 16:9 of their width; pages must still
    /// fill the capped card, not the full cell width.
    @Test func pagingPagesFillALandscapeCappedCard() {
        let band = HomeHeroCarouselCell.bandHeight(
            availableWidth: 820,
            containerHeight: 393,
            horizontalSizeClass: .compact
        )
        let cell = HomeHeroCarouselCell(
            frame: CGRect(x: 0, y: 0, width: 820, height: band)
        )
        cell.reload()
        cell.layoutIfNeeded()
        let scroll = cell.pagingScrollView
        #expect(scroll.bounds.width < 820 - 40)
        #expect(abs(scroll.bounds.width / scroll.bounds.height - 16.0 / 9.0) < 0.02)
        let looped = CGFloat(HomeHeroSlide.all.count + 2)
        #expect(
            abs(scroll.contentSize.width - scroll.bounds.width * looped) < 1
        )
    }
}
