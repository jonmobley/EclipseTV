//
//  ShowFormatFilterTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct ShowFormatFilterTests {

    private let albums = [
        LocalAlbum(name: "Wide", orientation: .landscape),
        LocalAlbum(name: "Tall", orientation: .portrait),
        LocalAlbum(name: "Wide 2", orientation: .landscape)
    ]

    @Test func defaultFilterIsAll() {
        #expect(ShowFormatFilter.all == .all)
        #expect(ShowFormatFilter(orientation: nil) == .all)
    }

    @Test func titlesMatchTheVisibleChips() {
        #expect(ShowFormatFilter.allCases.map(\.title) == [
            "All", "Horizontal", "Vertical"
        ])
    }

    @Test func allKeepsEveryShow() {
        let visible = ShowFormatFilter.albums(albums, matching: .all)
        #expect(visible.map(\.name) == ["Wide", "Tall", "Wide 2"])
    }

    @Test func horizontalKeepsLandscapeShows() {
        let visible = ShowFormatFilter.albums(albums, matching: .landscape)
        #expect(visible.map(\.name) == ["Wide", "Wide 2"])
    }

    @Test func verticalKeepsPortraitShows() {
        let visible = ShowFormatFilter.albums(albums, matching: .vertical)
        #expect(visible.map(\.name) == ["Tall"])
    }
}

@MainActor
struct ShowFormatFilterBarTests {

    @Test func allIsSelectedBlueByDefault() {
        let bar = ShowFormatFilterBar()
        #expect(bar.selected == .all)
        let all = chip(titled: "All", in: bar)
        let horizontal = chip(titled: "Horizontal", in: bar)
        #expect(all?.configuration?.baseBackgroundColor == UIColor.systemBlue)
        #expect(all?.configuration?.baseForegroundColor == UIColor.white)
        #expect(horizontal?.configuration?.baseBackgroundColor != UIColor.systemBlue)
        #expect(all?.accessibilityTraits.contains(.selected) == true)
    }

    @Test func tappingVerticalSelectsThatChip() {
        let bar = ShowFormatFilterBar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        var reported: ShowFormatFilter?
        bar.onSelect = { reported = $0 }
        chip(titled: "Vertical", in: bar)?.sendActions(for: .touchUpInside)
        #expect(bar.selected == .vertical)
        #expect(reported == .vertical)
        let vertical = chip(titled: "Vertical", in: bar)
        let all = chip(titled: "All", in: bar)
        #expect(vertical?.configuration?.baseBackgroundColor == UIColor.systemBlue)
        #expect(all?.configuration?.baseBackgroundColor != UIColor.systemBlue)
    }
}

@MainActor
struct HomeSectionHeaderFilterChipTests {

    @Test func selectedChipIsBlue() {
        let header = HomeSectionHeaderView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 92)
        )
        header.configure(
            title: "Recent",
            actions: [
                .init(title: "All", isSelected: true, handler: {}),
                .init(title: "Horizontal", isSelected: false, handler: {}),
                .init(title: "Vertical", isSelected: false, handler: {})
            ]
        )
        let all = chip(titled: "All", in: header)
        let horizontal = chip(titled: "Horizontal", in: header)
        #expect(all?.configuration?.baseBackgroundColor == UIColor.systemBlue)
        #expect(all?.configuration?.baseForegroundColor == UIColor.white)
        #expect(horizontal?.configuration?.baseBackgroundColor != UIColor.systemBlue)
    }
}

private func chip(titled title: String, in view: UIView) -> UIButton? {
    if let button = view as? UIButton, button.configuration?.title == title {
        return button
    }
    for sub in view.subviews {
        if let match = chip(titled: title, in: sub) { return match }
    }
    return nil
}
