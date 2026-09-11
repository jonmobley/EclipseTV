//
//  LivePollTapTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct LivePollTapTests {

    /// The first tap opens the room, instead of arming a Practice / Start gate:
    /// a poll card goes live like every other card in a Show. A card only
    /// rehearsing has no room either, so its tap starts one as well.
    @Test func aCardWithoutARoomStartsOnTheFirstTap() {
        #expect(
            LivePollTap.action(ownsRoom: false, roomIsOnProgram: false) == .start
        )
    }

    /// Tapping the live card re-syncs cues and status polling rather than
    /// reloading `/present` under the audience.
    @Test func theLiveCardRefreshesInsteadOfRepresenting() {
        #expect(
            LivePollTap.action(ownsRoom: true, roomIsOnProgram: true)
                == .refreshProjector
        )
    }

    /// A room survives switching to a photo, so its card puts it back up.
    @Test func anOpenRoomOffProgramGoesBackOnTheProjector() {
        #expect(
            LivePollTap.action(ownsRoom: true, roomIsOnProgram: false)
                == .presentRoom
        )
    }

    /// Another card's room on the projector does not make this card live.
    @Test func anotherCardsRoomStillStartsThisCard() {
        #expect(
            LivePollTap.action(ownsRoom: false, roomIsOnProgram: true) == .start
        )
    }
}
