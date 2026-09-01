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
        #expect(table.numberOfRows(inSection: 0) == 1)
        #expect(settings.tableView(table, titleForHeaderInSection: 0) == "Show")
        #expect(settings.tableView(table, titleForHeaderInSection: 1) == nil)
        #expect(settings.tableView(table, titleForHeaderInSection: 2) == "Playback")

        let nameCell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: 0)
        )
        let field = nameCell.contentView.subviews.compactMap { $0 as? UITextField }.first
        #expect(field?.text == "Go")
        #expect(field?.placeholder == "Show name")

        let delete = nameCell.accessoryView as? UIButton
        #expect(delete?.accessibilityLabel == "Delete Show")
        #expect(delete?.image(for: .normal) != nil)
    }

    @Test func openShowSettingsIncludesPracticeModeToggle() throws {
        let settings = SettingsViewController()
        settings.openShowName = "Go"
        settings.openShowId = UUID()
        settings.loadViewIfNeeded()

        let table = try #require(settings.tableView)
        #expect(table.numberOfRows(inSection: 1) == 1)
        #expect(
            settings.tableView(table, titleForFooterInSection: 1)
            == SettingsViewController.disconnectedLivePreviewFooter
        )

        let cell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: 1)
        )
        let config = cell.contentConfiguration as? UIListContentConfiguration
        #expect(config?.text == "Practice Mode")
        #expect(cell.accessoryView is UISwitch)
    }

    @Test func deleteShowAsksToConfirmBeforeCallingHost() throws {
        let settings = SettingsViewController()
        settings.openShowName = "Go"
        settings.openShowId = UUID()
        var didDelete = false
        settings.onDeleteShow = { didDelete = true }
        settings.loadViewIfNeeded()

        let nav = UINavigationController(rootViewController: settings)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()

        let table = try #require(settings.tableView)
        let nameCell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: 0)
        )
        let delete = try #require(nameCell.accessoryView as? UIButton)
        delete.sendActions(for: .touchUpInside)
        #expect(didDelete == false)
        #expect(settings.presentedViewController is UIAlertController)
        window.isHidden = true
    }

    @Test func homeSettingsOmitsShowSection() throws {
        let settings = SettingsViewController()
        settings.loadViewIfNeeded()

        let table = try #require(settings.tableView)
        let header = settings.tableView(table, titleForHeaderInSection: 0)
        #expect(header == "Playback")
    }
}
