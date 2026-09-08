//
//  CountdownRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct CountdownRibbonTests {

    // MARK: - Placement

    @Test func showsWhileThisShowsClockIsLive() {
        #expect(shouldShow())
    }

    @Test func hiddenOnHome() {
        #expect(shouldShow(isShowMode: false) == false)
    }

    @Test func hiddenWhenNoClockIsOnOutput() {
        #expect(shouldShow(isCountdownLive: false) == false)
    }

    @Test func hiddenWhenTheLiveClockBelongsToAnotherShow() {
        #expect(shouldShow(belongsToOpenShow: false) == false)
    }

    // MARK: - Selection

    @Test func presetDurationSelectsItsOwnChip() {
        let presets = CountdownController.durationPresets
        for (index, seconds) in presets.enumerated() {
            #expect(
                CountdownRibbon.selectedIndex(duration: seconds, presets: presets)
                    == index
            )
        }
    }

    @Test func customDurationSelectsTheTrailingCustomChip() {
        let presets = CountdownController.durationPresets
        #expect(
            CountdownRibbon.selectedIndex(duration: 450, presets: presets)
                == presets.count
        )
    }

    // MARK: - Helpers

    private func shouldShow(
        isShowMode: Bool = true,
        isCountdownLive: Bool = true,
        belongsToOpenShow: Bool = true
    ) -> Bool {
        CountdownRibbon.shouldShow(
            isShowMode: isShowMode,
            isCountdownLive: isCountdownLive,
            belongsToOpenShow: belongsToOpenShow
        )
    }
}
