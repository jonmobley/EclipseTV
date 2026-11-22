//
//  CameraKitTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import EclipsePhoneCameraProtocol
import Foundation
import Testing
@testable import EclipseiPhone

struct CameraKitTests {

    private let kitFrame = UUID()
    private let kitStill = UUID()
    private let ownFrame = UUID()
    private let ownStill = UUID()

    private func inputs(showsOwn: Bool) -> CameraPicturesSheetModel.Inputs {
        CameraPicturesSheetModel.Inputs(
            showName: "Sunday",
            kitFrames: [kitFrame],
            kitStills: [kitStill],
            ownFrames: [ownFrame],
            ownStills: [ownStill],
            showsOwn: showsOwn
        )
    }

    @Test func sheetListsKitFirstThenOwnPictures() {
        let sections = CameraPicturesSheetModel.sections(inputs(showsOwn: true))
        #expect(sections.map(\.title) == ["Sunday · Frames", "Sunday · Pictures", "My Frames", "My Pictures"])
        #expect(sections[0].entries == [.kitFrame(kitFrame)])
        #expect(sections[3].entries == [.ownStill(ownStill)])
    }

    @Test func lockedKitHidesOwnPictures() {
        let sections = CameraPicturesSheetModel.sections(inputs(showsOwn: false))
        #expect(sections.map(\.title) == ["Sunday · Frames", "Sunday · Pictures"])
        #expect(CameraPicturesSheetModel.frameRibbon(inputs(showsOwn: false)) == [.kitFrame(kitFrame)])
    }

    @Test func emptySectionsAreLeftOut() {
        let sections = CameraPicturesSheetModel.sections(.init(ownFrames: [ownFrame]))
        #expect(sections.map(\.title) == ["My Frames"])
    }

    @Test func frameRibbonPutsKitFramesFirst() {
        #expect(CameraPicturesSheetModel.frameRibbon(inputs(showsOwn: true)) == [.kitFrame(kitFrame), .ownFrame(ownFrame)])
    }

    @Test func onlyFramesGetCheckerboard() {
        #expect(CameraPictureEntry.kitFrame(kitFrame).isFrame)
        #expect(!CameraPictureEntry.ownStill(ownStill).isFrame)
    }

    @MainActor @Test func addingRules() {
        #expect(CameraPictureAdding.decide(isTwoWay: true, isLocked: true, ownRoomLeft: false))
        #expect(!CameraPictureAdding.decide(isTwoWay: false, isLocked: true, ownRoomLeft: true))
        #expect(CameraPictureAdding.decide(isTwoWay: false, isLocked: false, ownRoomLeft: true))
        #expect(!CameraPictureAdding.decide(isTwoWay: false, isLocked: false, ownRoomLeft: false))
    }

    @Test func stillRibbonPutsKitStillsBeforeOwnAndHidesOwnWhenLocked() {
        let open = CameraStillRibbon.items(cutawayIds: [ownStill], canAdd: true, kitIds: [kitStill])
        #expect(open == [.background, .cutaway(kitStill), .cutaway(ownStill), .add])
        let locked = CameraStillRibbon.items(cutawayIds: [ownStill], canAdd: false, kitIds: [kitStill], showsOwn: false)
        #expect(locked == [.background, .cutaway(kitStill)])
    }

    @Test func uploadPlanSplitsUnderMacCap() {
        let chunk = PhoneCameraKitRoute.uploadChunkBytes
        let plan = CameraKitUploadPlan(byteCount: chunk * 2 + 10)
        #expect(plan.chunkCount == 3)
        #expect(plan.range(of: 2) == (chunk * 2)..<(chunk * 2 + 10))
        #expect(CameraKitUploadPlan(byteCount: 0).chunkCount == 1)
    }

    @Test func cacheNameChangesWithVersion() {
        let first = PhoneCameraKitItem(id: "a", kind: .frame, name: "", orientation: .landscape, version: "1-2")
        let second = PhoneCameraKitItem(id: "a", kind: .frame, name: "", orientation: .landscape, version: "1-3")
        #expect(CameraKitUploadPlan.cacheName(for: first) != CameraKitUploadPlan.cacheName(for: second))
    }
}
