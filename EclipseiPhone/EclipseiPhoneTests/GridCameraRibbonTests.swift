//
//  GridCameraRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// The ribbon under the live camera hero: frames, then Background, then quick changes.
struct GridCameraRibbonTests {

    @Test func framesThenBackgroundThenQuickChanges() {
        let frame = UUID(), still = UUID()
        #expect(GridCameraRibbonItem.items(
            frameIds: [frame], hasBackground: true, cutawayIds: [still]
        ) == [.frame(frame), .background, .cutaway(still)])
    }

    @Test func noBackgroundTileWithoutABackground() {
        let still = UUID()
        #expect(GridCameraRibbonItem.items(
            frameIds: [], hasBackground: false, cutawayIds: [still]
        ) == [.cutaway(still)])
    }

    /// VoiceOver hears which frame is on; stills carry no On / Off.
    @Test func framesSpeakOnOrOff() {
        let on = UUID(), off = UUID()
        #expect(GridCameraRibbonItem.frame(on).spokenState(selectedFrameId: on) == "On")
        #expect(GridCameraRibbonItem.frame(off).spokenState(selectedFrameId: on) == "Off")
        #expect(GridCameraRibbonItem.frame(off).spokenState(selectedFrameId: nil) == "Off")
        #expect(GridCameraRibbonItem.background.spokenState(selectedFrameId: on) == nil)
        #expect(GridCameraRibbonItem.cutaway(on).spokenState(selectedFrameId: on) == nil)
    }

    @Test func emptyWhenNothingToShow() {
        #expect(GridCameraRibbonItem.items(
            frameIds: [], hasBackground: false, cutawayIds: []
        ).isEmpty)
    }
}
