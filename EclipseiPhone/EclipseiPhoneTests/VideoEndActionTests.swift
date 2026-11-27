//
//  VideoEndActionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct VideoEndActionTests {

    // MARK: - Old data

    @Test func olderLibraryListsDecodeToTheOldBehavior() throws {
        let looping = Data(#"{"id":"a.mp4","name":"a","isVideo":true,"duration":4,"isLooping":true}"#.utf8)
        let plain = Data(#"{"id":"b.mp4","name":"b","isVideo":true,"duration":4,"isLooping":false}"#.utf8)
        let bare = Data(#"{"id":"c.mp4","name":"c","isVideo":true,"duration":4}"#.utf8)
        let decoder = JSONDecoder()
        #expect(try decoder.decode(LibraryItemDTO.self, from: looping).videoEndAction == .loop)
        #expect(try decoder.decode(LibraryItemDTO.self, from: plain).videoEndAction == .pause)
        let decoded = try decoder.decode(LibraryItemDTO.self, from: bare)
        #expect(decoded.endAction == nil)
        #expect(decoded.videoEndAction == .pause)
    }

    @Test func choiceSurvivesSaving() throws {
        var item = LibraryItemDTO(id: "a.mp4", name: "a", isVideo: true, duration: 4)
        item.endAction = VideoEndAction.next.rawValue
        let decoded = try JSONDecoder().decode(
            LibraryItemDTO.self, from: JSONEncoder().encode(item)
        )
        #expect(decoded.videoEndAction == .next)
    }

    // MARK: - Resolve

    @Test func loopFlagAlwaysWins() {
        #expect(VideoEndAction.resolve(isLooping: true, stored: "next") == .loop)
    }

    @Test func storedChoiceAppliesWhenNotLooping() {
        #expect(VideoEndAction.resolve(isLooping: false, stored: "next") == .next)
        #expect(VideoEndAction.resolve(isLooping: nil, stored: "screensaver") == .screensaver)
    }

    @Test func staleLoopChoiceAndUnknownTokensFallBackToPause() {
        #expect(VideoEndAction.resolve(isLooping: false, stored: "loop") == .pause)
        #expect(VideoEndAction.resolve(isLooping: false, stored: "explode") == .pause)
        #expect(VideoEndAction.resolve(isLooping: nil, stored: nil) == .pause)
    }

    // MARK: - Decision

    @Test func nextAndScreensaverTakeOverOutput() {
        #expect(decide(.next) == .next)
        #expect(decide(.screensaver) == .screensaver)
    }

    @Test func pauseAndLoopLeaveOutputAlone() {
        #expect(decide(.pause) == .stay)
        #expect(decide(.loop) == .stay)
    }

    @Test func staysWhenThisPhoneDoesNotOwnLiveOutput() {
        #expect(decide(.next, isVideoLive: false) == .stay)
        #expect(decide(.next, isRemoteOperator: true) == .stay)
        #expect(decide(.screensaver, isOutputLocked: true) == .stay)
        #expect(decide(.screensaver, isPhonePreview: true) == .stay)
        #expect(decide(.next, isBlackoutHolding: true) == .stay)
    }

    // MARK: - Next item

    @Test func nextItemSkipsTilesThatNeedAPerson() {
        let video = LibraryItemDTO(id: "a.mp4", name: "a", isVideo: true, duration: 4)
        let items: [ShowGridItem] = [.logo, .media(video), .camera, .screensaver]
        #expect(LibraryGridViewController.itemAfterVideo("a.mp4", in: items) == .screensaver)
    }

    @Test func nextItemIsNilAtTheLastCard() {
        let video = LibraryItemDTO(id: "a.mp4", name: "a", isVideo: true, duration: 4)
        let items: [ShowGridItem] = [.logo, .media(video), .camera]
        #expect(LibraryGridViewController.itemAfterVideo("a.mp4", in: items) == nil)
        #expect(LibraryGridViewController.itemAfterVideo("missing.mp4", in: items) == nil)
    }

    // MARK: - Helpers

    private func decide(
        _ action: VideoEndAction,
        isVideoLive: Bool = true,
        isRemoteOperator: Bool = false,
        isOutputLocked: Bool = false,
        isPhonePreview: Bool = false,
        isBlackoutHolding: Bool = false
    ) -> VideoEndDecision {
        VideoEndDecision.decide(
            action: action,
            isVideoLive: isVideoLive,
            isRemoteOperator: isRemoteOperator,
            isOutputLocked: isOutputLocked,
            isPhonePreview: isPhonePreview,
            isBlackoutHolding: isBlackoutHolding
        )
    }
}
