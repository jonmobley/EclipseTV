//
//  SettingsShowEditingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct SettingsShowEditingTests {

    @Test func openShowSettingsUsesNameFieldInsteadOfArrangeAndRename() throws {
        let settings = SettingsViewController()
        settings.openShowName = "Go"
        settings.openShowId = UUID()
        settings.loadViewIfNeeded()

        let table = try #require(settings.tableView)
        #expect(table.numberOfRows(inSection: 0) == 2)
        #expect(settings.tableView(table, titleForHeaderInSection: 0) == "Show")
        #expect(settings.tableView(table, titleForHeaderInSection: 1) == "Playback")

        let nameCell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: 0)
        )
        let field = nameCell.contentView.subviews.compactMap { $0 as? UITextField }.first
        #expect(field?.text == "Go")
        #expect(field?.placeholder == "Show name")

        let deleteCell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 1, section: 0)
        )
        let config = deleteCell.contentConfiguration as? UIListContentConfiguration
        #expect(config?.text == "Delete Show")
    }

    @Test func homeSettingsOmitsShowSection() throws {
        let settings = SettingsViewController()
        settings.loadViewIfNeeded()

        let table = try #require(settings.tableView)
        let header = settings.tableView(table, titleForHeaderInSection: 0)
        #expect(header == "Playback")
    }
}
