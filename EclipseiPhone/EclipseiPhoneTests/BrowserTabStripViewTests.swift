//
//  BrowserTabStripViewTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// The tab row ends in ⊕, and keeps the active tab (plus ⊕ after the last one) in view.
@MainActor
struct BrowserTabStripViewTests {

    private func pages(_ titles: [String]) -> [WebPage] {
        titles.map { WebPage(title: $0, url: URL(string: "https://\($0.lowercased().replacingOccurrences(of: " ", with: "-")).example.com")!) }
    }

    private func scrollView(of strip: BrowserTabStripView) throws -> UIScrollView {
        try #require(strip.subviews.compactMap { $0 as? UIScrollView }.first)
    }

    @Test func newTabButtonComesAfterTheLastTab() throws {
        let sites = pages(["Alpha", "Bravo", "Charlie"])
        let list = BrowserTabList(pages: sites, active: sites[0])
        let strip = BrowserTabStripView(frame: CGRect(x: 0, y: 0, width: 800, height: 34))
        var tapped = 0
        strip.onNewTab = { tapped += 1 }
        strip.update(tabs: list.tabs, activeId: list.activeId, tvTabId: nil)
        strip.layoutIfNeeded()

        let plus = strip.newTabButton
        let chips = try scrollView(of: strip).subviews.first?.subviews
            .compactMap { $0 as? BrowserTabChip } ?? []
        #expect(chips.count == 3)
        let lastChipMaxX = chips.map { $0.frame.maxX }.max() ?? 0
        #expect(plus.frame.minX > lastChipMaxX)
        plus.sendActions(for: .touchUpInside)
        #expect(tapped == 1)
    }

    @Test func aNarrowRowShowsTheLastActiveTabAndThePlus() throws {
        let sites = pages(["Alpha Site", "Bravo Site", "Charlie Site", "Delta Site"])
        let list = BrowserTabList(pages: sites, active: sites[3])
        let strip = BrowserTabStripView(frame: .zero)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        window.addSubview(strip)
        // As in the browser: chips arrive before the row has its width.
        strip.update(tabs: list.tabs, activeId: list.activeId, tvTabId: nil)
        strip.layoutIfNeeded()
        strip.frame = CGRect(x: 0, y: 0, width: 220, height: 34)
        strip.layoutIfNeeded()

        let scroll = try scrollView(of: strip)
        let plus = strip.newTabButton.convert(strip.newTabButton.bounds, to: strip)
        #expect(scroll.contentSize.width > 220)
        #expect(plus.maxX <= strip.bounds.maxX + 0.5)
        #expect(plus.minX >= 0)
    }
}
