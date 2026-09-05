//
//  LibraryThumbnailCellLivePollTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LibraryThumbnailCellLivePollTests {

    @Test func applySpecialTitleKeepsMoreMenu() {
        let cell = LibraryThumbnailCell(
            frame: CGRect(x: 0, y: 0, width: 160, height: 90)
        )
        cell.configureSpecial(
            title: "Session 1",
            systemImage: "chart.bar.fill",
            thumbnail: nil,
            fillColor: UIColor(white: 0.12, alpha: 1),
            isLive: true,
            typeIcon: .livePoll
        )
        cell.setMoreMenu(UIMenu(children: [
            UIAction(title: "End Poll") { _ in }
        ]))
        #expect(cell.moreButton.isHidden == false)

        cell.applySpecialTitle(
            "Session 1\nABCD · 3 votes",
            isLive: true,
            typeIcon: .livePoll
        )
        #expect(cell.captionLabel.text == "Session 1\nABCD · 3 votes")
        #expect(cell.moreButton.isHidden == false)
        #expect(cell.moreButton.menu != nil)
    }
}
