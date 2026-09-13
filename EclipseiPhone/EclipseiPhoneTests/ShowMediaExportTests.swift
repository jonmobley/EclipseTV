//
//  ShowMediaExportTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct ShowMediaExportTests {

    // MARK: - File names

    @Test func sanitizeStripsPathBreakersAndCollapsesSpace() {
        #expect(ExportFileName.sanitize("  A/B:C*D?  ") == "A_B_C_D")
        #expect(ExportFileName.sanitize("...") == "Untitled")
        #expect(ExportFileName.sanitize("   ") == "Untitled")
        #expect(ExportFileName.sanitize("Hello   World") == "Hello World")
    }

    @Test func numberedPadsToAtLeastTwoDigits() {
        #expect(ExportFileName.numbered("Intro", index: 1, totalCount: 9) == "01 Intro")
        #expect(
            ExportFileName.numbered("Finale", index: 12, totalCount: 100)
                == "012 Finale"
        )
    }

    @Test func fileNameKeepsSafeExtension() {
        #expect(
            ExportFileName.fileName(base: "01 Clip", pathExtension: "MOV")
                == "01 Clip.mov"
        )
        #expect(
            ExportFileName.fileName(base: "Notes", pathExtension: "")
                == "Notes"
        )
    }

    // MARK: - Planner

    @Test func planNumbersMediaAndNestsSlideshowSlides() {
        let nodes: [ShowMediaExportPlanner.Node] = [
            .file(title: "Welcome", pathExtension: "jpg"),
            .slideshow(name: "Opening", slides: [
                .init(title: "Slide A", pathExtension: "jpg"),
                .init(title: "Slide B", pathExtension: "png")
            ]),
            .file(title: "Bulletin", pathExtension: "pdf")
        ]
        let planned = ShowMediaExportPlanner.plan(nodes: nodes)
        #expect(planned.map(\.relativePath) == [
            "01 Welcome.jpg",
            "02 Opening/01 Slide A.jpg",
            "02 Opening/02 Slide B.png",
            "03 Bulletin.pdf"
        ])
        #expect(planned.map(\.sourceIndex) == [0, 1, 2, 3])
    }

    @Test func planReturnsEmptyForEmptyNodes() {
        #expect(ShowMediaExportPlanner.plan(nodes: []).isEmpty)
    }

    // MARK: - ZIP

    @Test func zipWriterRoundTripsStoredEntries() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try Data("alpha".utf8).write(to: a)
        try Data("bravo".utf8).write(to: b)

        let zipURL = dir.appendingPathComponent("out.zip")
        try ZipStoreWriter.write(
            entries: [
                (relativePath: "01 Hello.txt", sourceURL: a),
                (relativePath: "02 Deck/01 Slide.txt", sourceURL: b)
            ],
            to: zipURL
        )

        let data = try Data(contentsOf: zipURL)
        #expect(data.count > 30)
        // Local file header signatures for both entries.
        let sig = Data([0x50, 0x4b, 0x03, 0x04])
        var count = 0
        var search = data.startIndex
        while let range = data.range(of: sig, in: search..<data.endIndex) {
            count += 1
            search = range.upperBound
        }
        #expect(count == 2)
        #expect(String(data: data, encoding: .isoLatin1)?.contains("01 Hello.txt") == true)
        #expect(
            String(data: data, encoding: .isoLatin1)?
                .contains("02 Deck/01 Slide.txt") == true
        )
    }
}

@MainActor
struct ShowMediaExportSettingsTests {

    @Test func openShowSettingsIncludesExportMediaRow() throws {
        let settings = SettingsViewController()
        settings.openShowName = "Go"
        settings.openShowId = UUID()
        settings.loadViewIfNeeded()

        let table = try #require(settings.tableView)
        let sharing = (0..<table.numberOfSections).first {
            settings.tableView(table, titleForHeaderInSection: $0) == "Show Sharing"
        }
        let section = try #require(sharing)
        #expect(table.numberOfRows(inSection: section) == 3)

        let exportCell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 1, section: section)
        )
        let config = exportCell.contentConfiguration as? UIListContentConfiguration
        #expect(config?.text == "Export media")

        var exported = false
        settings.onExportShowMedia = { exported = true }
        settings.tableView(
            table, didSelectRowAt: IndexPath(row: 1, section: section)
        )
        #expect(exported)
    }
}
