//
//  GettingStartedGuideTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The guide sizes its hero header by hand in `viewDidLayoutSubviews`, and assigning
//  `tableHeaderView` schedules another layout pass. When the header was self-sizing
//  (`translatesAutoresizingMaskIntoConstraints = false`) Auto Layout rewrote the frame
//  after every assignment, so the size check never settled: opening Getting Started
//  spun the main thread at 100% CPU until the watchdog killed the app.
//
//  These check that the sizing step converges rather than that it merely runs, so a
//  regression fails instead of hanging the test process.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct GettingStartedGuideTests {

    private static let widths: [CGFloat] = [0, 320, 390, 430, 744, 1024]

    /// A guide whose table is already `tableWidth` wide.
    ///
    /// `UITableView` rewrites `tableHeaderView.frame.width` to its own width when the
    /// header is assigned, so sizing the header to a width the table does not have can
    /// never settle. The guide only ever passes `tableView.bounds.width`.
    private static func loadedGuide(tableWidth: CGFloat) -> GettingStartedViewController {
        let guide = GettingStartedViewController()
        guide.loadViewIfNeeded()
        guide.tableView.frame = CGRect(x: 0, y: 0, width: tableWidth, height: 800)
        return guide
    }

    /// One pass may resize; the next must report nothing left to do.
    @Test func heroHeaderSizingSettlesAfterOnePass() {
        for width in Self.widths {
            let guide = Self.loadedGuide(tableWidth: width)

            _ = guide.resizeHeroHeader(toWidth: width)
            #expect(
                !guide.resizeHeroHeader(toWidth: width),
                "hero header never settled at width \(width) — viewDidLayoutSubviews loops"
            )
        }
    }

    /// A frame-based header is what keeps the loop above from restarting.
    @Test func heroHeaderIsFrameBased() {
        let guide = GettingStartedViewController()
        guide.loadViewIfNeeded()
        let header = guide.tableView.tableHeaderView
        #expect(header?.translatesAutoresizingMaskIntoConstraints == true)
    }

    @Test func heroHeaderGetsRealHeightForTheTableWidth() {
        let guide = Self.loadedGuide(tableWidth: 390)
        guide.resizeHeroHeader(toWidth: 390)

        guard let header = guide.tableView.tableHeaderView else {
            Issue.record("guide has no hero header")
            return
        }
        #expect(header.frame.width == 390)
        #expect(header.frame.height > 0)
    }

    /// Every topic renders; the guide is section-per-topic with one row each.
    @Test func everyTopicGetsItsOwnSection() {
        let guide = GettingStartedViewController()
        guide.loadViewIfNeeded()
        let table: UITableView = guide.tableView

        #expect(table.numberOfSections > 0)
        for section in 0..<table.numberOfSections {
            #expect(table.numberOfRows(inSection: section) == 1)
            let cell = guide.tableView(
                table, cellForRowAt: IndexPath(row: 0, section: section)
            )
            #expect(cell is GettingStartedTopicCell, "section \(section) fell back to a stub")
        }
    }
}
