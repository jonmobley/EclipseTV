//
//  GettingStartedGuideTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct GettingStartedGuideTests {

    /// Every topic renders; the guide is section-per-topic with one row each.
    @Test func everyTopicGetsItsOwnSection() {
        let guide = GettingStartedViewController()
        guide.loadViewIfNeeded()
        let table: UITableView = guide.tableView

        #expect(table.numberOfSections > 0)
        #expect(table.tableHeaderView == nil)
        for section in 0..<table.numberOfSections {
            #expect(table.numberOfRows(inSection: section) == 1)
            let cell = guide.tableView(
                table, cellForRowAt: IndexPath(row: 0, section: section)
            )
            #expect(cell is GettingStartedTopicCell, "section \(section) fell back to a stub")
        }
    }
}
