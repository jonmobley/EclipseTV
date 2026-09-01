//
//  SettingsGuidedAccessTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct SettingsGuidedAccessTests {

    @Test func homeSettingsIncludesGuidedAccessRecommendation() throws {
        let settings = SettingsViewController()
        settings.loadViewIfNeeded()
        let table = try #require(settings.tableView)
        let section = try #require(recommendationSection(in: settings))

        #expect(
            settings.tableView(table, titleForHeaderInSection: section)
            == GuidedAccessRecommendation.settingsHeader
        )
        #expect(
            settings.tableView(table, titleForFooterInSection: section)
            == GuidedAccessRecommendation.settingsFooter
        )
        #expect(table.numberOfRows(inSection: section) == 1)

        let cell = settings.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: section)
        )
        let config = cell.contentConfiguration as? UIListContentConfiguration
        #expect(config?.text == GuidedAccessRecommendation.rowTitle)
        #expect(config?.secondaryText == GuidedAccessRecommendation.statusText)
        #expect(cell.accessoryType == .disclosureIndicator)
    }

    @Test func selectingGuidedAccessPushesHowTo() throws {
        let settings = SettingsViewController()
        settings.loadViewIfNeeded()
        let nav = UINavigationController(rootViewController: settings)
        let table = try #require(settings.tableView)
        let section = try #require(recommendationSection(in: settings))

        settings.tableView(table, didSelectRowAt: IndexPath(row: 0, section: section))
        #expect(nav.topViewController is SettingsGuidedAccessViewController)
    }

    @Test func howToListsStatusWhyAndSteps() throws {
        let detail = SettingsGuidedAccessViewController()
        detail.loadViewIfNeeded()
        let table = try #require(detail.tableView)

        #expect(table.numberOfSections == 3)
        #expect(table.numberOfRows(inSection: 0) == 1)
        #expect(table.numberOfRows(inSection: 1) == 1)
        #expect(
            table.numberOfRows(inSection: 2)
            == GuidedAccessRecommendation.howSteps.count
        )
        #expect(
            detail.tableView(table, titleForHeaderInSection: 1)
            == GuidedAccessRecommendation.whyTitle
        )
        #expect(
            detail.tableView(table, titleForHeaderInSection: 2)
            == GuidedAccessRecommendation.howTitle
        )

        let status = detail.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: 0)
        )
        let statusConfig = status.contentConfiguration as? UIListContentConfiguration
        #expect(statusConfig?.text == GuidedAccessRecommendation.rowTitle)
        #expect(statusConfig?.secondaryText == GuidedAccessRecommendation.statusText)

        let why = detail.tableView(
            table, cellForRowAt: IndexPath(row: 0, section: 1)
        )
        let whyConfig = why.contentConfiguration as? UIListContentConfiguration
        #expect(whyConfig?.text == GuidedAccessRecommendation.whyBody)

        for (index, step) in GuidedAccessRecommendation.howSteps.enumerated() {
            let cell = detail.tableView(
                table, cellForRowAt: IndexPath(row: index, section: 2)
            )
            let config = cell.contentConfiguration as? UIListContentConfiguration
            #expect(config?.text == "\(index + 1). \(step)")
        }
    }

    private func recommendationSection(in settings: SettingsViewController) -> Int? {
        guard let table = settings.tableView else { return nil }
        for section in 0..<table.numberOfSections {
            if settings.tableView(table, titleForHeaderInSection: section)
                == GuidedAccessRecommendation.settingsHeader {
                return section
            }
        }
        return nil
    }
}
