//
//  ExternalOutputSettingsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
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
}
