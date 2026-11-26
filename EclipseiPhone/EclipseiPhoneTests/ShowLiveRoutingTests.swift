//
//  ShowLiveRoutingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowLiveRoutingTests {

    @Test func practiceWithoutDisplayDoesNotAdvertise() {
        #expect(
            ShowLiveRouting.shouldAdvertise(
                hasExternalDisplay: false,
                isShowOpen: true,
                isRemoteOperator: false
            ) == false
        )
    }

    @Test func hdmiOpenShowAdvertises() {
        #expect(
            ShowLiveRouting.shouldAdvertise(
                hasExternalDisplay: true,
                isShowOpen: true,
                isRemoteOperator: false
            )
        )
    }

    @Test func operatorDoesNotAdvertiseEvenWithHDMI() {
        #expect(
            ShowLiveRouting.shouldAdvertise(
                hasExternalDisplay: true,
                isShowOpen: true,
                isRemoteOperator: true
            ) == false
        )
    }

    @Test func closedShowDoesNotAdvertise() {
        #expect(
            ShowLiveRouting.shouldAdvertise(
                hasExternalDisplay: true,
                isShowOpen: false,
                isRemoteOperator: false
            ) == false
        )
    }

    @Test func joinRequiresMatchingShowAndUser() {
        let show = UUID()
        let user = ShowLiveRouting.hashedUserId("ck-user-a")
        #expect(
            ShowLiveRouting.canAutoJoin(
                advertisedShowId: show,
                advertisedUserHash: user,
                localShowId: show,
                localUserHash: user
            )
        )
        #expect(
            ShowLiveRouting.canAutoJoin(
                advertisedShowId: UUID(),
                advertisedUserHash: user,
                localShowId: show,
                localUserHash: user
            ) == false
        )
        #expect(
            ShowLiveRouting.canAutoJoin(
                advertisedShowId: show,
                advertisedUserHash: ShowLiveRouting.hashedUserId("ck-user-b"),
                localShowId: show,
                localUserHash: user
            ) == false
        )
        #expect(
            ShowLiveRouting.canAutoJoin(
                advertisedShowId: show,
                advertisedUserHash: user,
                localShowId: show,
                localUserHash: nil
            ) == false
        )
    }

    @Test func hashedUserIdIsStableAndShort() {
        let hash = ShowLiveRouting.hashedUserId("record-name")
        #expect(hash == ShowLiveRouting.hashedUserId("record-name"))
        #expect(hash.count == 16)
        #expect(hash != ShowLiveRouting.hashedUserId("other-record"))
    }

    @Test func browseBeforeAdvertiseYieldsWhenDirectorExists() {
        #expect(
            ShowLiveRouting.shouldBecomeDirectorAfterElection(
                foundDirector: true,
                hasExternalDisplay: true,
                isRemoteOperator: false
            ) == false
        )
        #expect(
            ShowLiveRouting.shouldBecomeDirectorAfterElection(
                foundDirector: false,
                hasExternalDisplay: true,
                isRemoteOperator: false
            )
        )
        #expect(
            ShowLiveRouting.shouldBecomeDirectorAfterElection(
                foundDirector: false,
                hasExternalDisplay: false,
                isRemoteOperator: false
            ) == false
        )
    }

    @Test func operatorInterceptsLocalPresent() {
        #expect(ShowLiveRouting.shouldCommandDirector(isRemoteOperator: true))
        #expect(
            ShowLiveRouting.shouldCommandDirector(isRemoteOperator: false) == false
        )
    }

    @Test func operatorRoleWaitsForADirectorThatActsOnCommands() {
        #expect(
            ShowLiveRouting.shouldBecomeRemoteOperator(
                foundDirector: true,
                directorAppliesSelects: true
            )
        )
        // Giving up local output to a director that drops commands loses the tap
        // on both devices, so the peer stays a plain device instead.
        #expect(
            ShowLiveRouting.shouldBecomeRemoteOperator(
                foundDirector: true,
                directorAppliesSelects: false
            ) == false
        )
        #expect(
            ShowLiveRouting.shouldBecomeRemoteOperator(
                foundDirector: false,
                directorAppliesSelects: true
            ) == false
        )
    }

    @Test func operatorRoleIsOnWhileTheDirectorObservesSelects() {
        // Paired with the `incomingSelectNotification` observer in
        // `LibraryGridViewController`: both must change together, so this fails
        // the moment one moves alone.
        #expect(ShowLiveRouting.directorAppliesSelects)
    }

    @Test func slideStepTakesWholeSlidesWithinReason() {
        #expect(ShowLiveRouting.slideStep(1) == 1)
        #expect(ShowLiveRouting.slideStep(-1) == -1)
        #expect(ShowLiveRouting.slideStep(2.9) == 2)
        #expect(ShowLiveRouting.slideStep(0) == nil)
        #expect(ShowLiveRouting.slideStep(0.4) == nil)
        #expect(ShowLiveRouting.slideStep(nil) == nil)
        #expect(ShowLiveRouting.slideStep(.nan) == nil)
        #expect(ShowLiveRouting.slideStep(.infinity) == nil)
        #expect(ShowLiveRouting.slideStep(1e12) == nil)
    }

    @Test func slideIndexMustBeASlideTheDirectorHas() {
        #expect(ShowLiveRouting.slideIndex(0, count: 3) == 0)
        #expect(ShowLiveRouting.slideIndex(2, count: 3) == 2)
        #expect(ShowLiveRouting.slideIndex(3, count: 3) == nil)
        #expect(ShowLiveRouting.slideIndex(-1, count: 3) == nil)
        #expect(ShowLiveRouting.slideIndex(0, count: 0) == nil)
        #expect(ShowLiveRouting.slideIndex(.nan, count: 3) == nil)
        #expect(ShowLiveRouting.slideIndex(1e300, count: 3) == nil)
        #expect(ShowLiveRouting.slideIndex(nil, count: 3) == nil)
    }
}
