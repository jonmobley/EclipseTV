//
//  ExternalOutputSettingsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
struct ExternalOutputSettingsTests {

    @Test func newShowDefaultsToLandscape() {
        let album = LocalAlbum(name: "Stage")
        #expect(album.orientation == .landscape)
    }

    @Test func restoreLandscapeDependsOnVerticalShows() {
        let previous = ExternalOutputSettings.orientation
        defer { ExternalOutputSettings.orientation = previous }

        ExternalOutputSettings.orientation = .portrait
        ExternalOutputSettings.restoreLandscapeIfNoVerticalShows([])
        #expect(ExternalOutputSettings.orientation == .landscape)

        ExternalOutputSettings.orientation = .portrait
        let shows = [LocalAlbum(name: "Tall", orientation: .portrait)]
        ExternalOutputSettings.restoreLandscapeIfNoVerticalShows(shows)
        #expect(ExternalOutputSettings.orientation == .portrait)
    }

    @Test func webLogicalWidthsUseDesktopBreakpoints() {
        #expect(WebTextSize.large.logicalWidth == 1024)
        #expect(WebTextSize.medium.logicalWidth == 1280)
        #expect(WebTextSize.small.logicalWidth == 1440)
        #expect(WebTextSize.small.logicalWidth > WebTextSize.medium.logicalWidth)
        #expect(WebTextSize.medium.logicalWidth > WebTextSize.large.logicalWidth)
    }

    @Test func phoneColumnCountsStayAtTheModeBaseline() {
        let inset: CGFloat = 16
        let spacing: CGFloat = 12
        #expect(
            ExternalOutputOrientation.landscape.gridColumnCount(
                forWidth: 390, sectionInset: inset, spacing: spacing
            ) == 2
        )
        #expect(
            ExternalOutputOrientation.portrait.gridColumnCount(
                forWidth: 390, sectionInset: inset, spacing: spacing
            ) == 3
        )
        #expect(
            ExternalOutputOrientation.portrait.gridColumnCount(
                forWidth: 780, sectionInset: inset, spacing: spacing
            ) == 4
        )
    }

    @Test func thirteenInchDoesNotExceedFourColumns() {
        let inset: CGFloat = 16
        let spacing: CGFloat = 12
        for orientation in ExternalOutputOrientation.allCases {
            #expect(
                orientation.gridColumnCount(
                    forWidth: 1366, sectionInset: inset, spacing: spacing
                ) == ExternalOutputOrientation.maxGridColumnCount
            )
        }
    }

    @Test func pauseMusicForVideoDefaultsOff() {
        let key = "EclipseTV.audio.pauseMusicForVideo"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #expect(ExternalOutputSettings.pauseMusicForVideo == false)
    }
}
