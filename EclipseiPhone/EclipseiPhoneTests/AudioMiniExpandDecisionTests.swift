//
//  AudioMiniExpandDecisionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct AudioMiniExpandDecisionTests {

    @Test func trackChosenInThePickerExpandsTheCard() {
        #expect(
            AudioMiniExpandDecision.shouldExpandCard(
                sessionJustStarted: true,
                startedFromPicker: true,
                usesDrawerChrome: false
            )
        )
    }

    @Test func playbackStartedOutsideThePickerLeavesChromeAlone() {
        #expect(
            !AudioMiniExpandDecision.shouldExpandCard(
                sessionJustStarted: true,
                startedFromPicker: false,
                usesDrawerChrome: false
            )
        )
    }

    /// Skipping to the next track inside an open picker is not a new session.
    @Test func changesWithinARunningSessionDoNotReExpand() {
        #expect(
            !AudioMiniExpandDecision.shouldExpandCard(
                sessionJustStarted: false,
                startedFromPicker: true,
                usesDrawerChrome: false
            )
        )
    }

    /// Regular width keeps Music in the drawer; the card never appears there.
    @Test func drawerChromeNeverExpandsTheCard() {
        #expect(
            !AudioMiniExpandDecision.shouldExpandCard(
                sessionJustStarted: true,
                startedFromPicker: true,
                usesDrawerChrome: true
            )
        )
    }
}
