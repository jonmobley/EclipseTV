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
}
