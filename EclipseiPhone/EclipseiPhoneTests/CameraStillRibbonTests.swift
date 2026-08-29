//
//  CameraStillRibbonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CameraStillRibbonTests {

    @Test func ribbonStartsWithBackgroundAndEndsWithAdd() {
        let items = CameraStillRibbon.items(cutawayIds: [], canAdd: true)
        #expect(items == [.background, .add])
    }

    @Test func addCreatesAnotherQuickChangeStill() {
        let first = UUID()
        let second = UUID()
        let items = CameraStillRibbon.items(
            cutawayIds: [first, second],
            canAdd: true
        )
        #expect(items == [
            .background,
            .cutaway(first),
            .cutaway(second),
            .add
        ])
    }

    @Test func addCellHidesWhenAtCapacity() {
        let items = CameraStillRibbon.items(
            cutawayIds: [UUID()],
            canAdd: false
        )
        #expect(items.contains(.add) == false)
        #expect(items.first == .background)
    }

    @Test func cameraTileIsLiveForFeedOrQuickChangePark() {
        #expect(
            CameraStillRibbon.cameraTileIsLive(isCameraLive: true, parked: nil)
                == true
        )
        #expect(
            CameraStillRibbon.cameraTileIsLive(
                isCameraLive: false,
                parked: .cutaway(UUID())
            ) == true
        )
        #expect(
            CameraStillRibbon.cameraTileIsLive(
                isCameraLive: false,
                parked: .background
            ) == false
        )
        #expect(
            CameraStillRibbon.cameraTileIsLive(isCameraLive: false, parked: nil)
            == false
        )
    }

    @Test func closingOnBackgroundCommitsToBackgroundTile() {
        #expect(
            CameraStillRibbon.shouldCommitToBackground(parked: .background)
                == true
        )
        #expect(
            CameraStillRibbon.shouldCommitToBackground(parked: .cutaway(UUID()))
            == false
        )
        #expect(CameraStillRibbon.shouldCommitToBackground(parked: nil) == false)
    }
}
