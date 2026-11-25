//
//  LiveOutputHoldStateTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// Freeze / White rules, and how they stay safe with older Show Live peers.
struct LiveOutputHoldStateTests {

    // MARK: Freeze vs Lock

    @Test func freezeTurnsLockOff() {
        var state = LiveOutputHoldState()
        state.setLocked(true)
        let rFreeze = state.toggleFreeze()
        #expect(rFreeze)
        #expect(state.isFrozen)
        #expect(state.isLocked == false)
    }

    @Test func lockTurnsFreezeOff() {
        var state = LiveOutputHoldState()
        state.toggleFreeze()
        state.setLocked(true)
        #expect(state.isLocked)
        #expect(state.isFrozen == false)
    }

    @Test func unfreezingRestoresLive() {
        var state = LiveOutputHoldState()
        state.toggleFreeze()
        let rFreeze = state.toggleFreeze()
        #expect(rFreeze == false)
        #expect(state == LiveOutputHoldState())
    }

    // MARK: White vs Blackout

    @Test func whiteTurnsBlackoutOff() {
        var state = LiveOutputHoldState()
        state.setBlack(true)
        let rWhite = state.toggleWhite()
        #expect(rWhite)
        #expect(state.isWhite)
        #expect(state.isBlack == false)
    }

    @Test func blackoutTurnsWhiteOff() {
        var state = LiveOutputHoldState()
        state.toggleWhite()
        state.setBlack(true)
        #expect(state.isBlack)
        #expect(state.isWhite == false)
    }

    @Test func whiteTogglesBackOff() {
        var state = LiveOutputHoldState()
        state.toggleWhite()
        let rWhite = state.toggleWhite()
        #expect(rWhite == false)
        #expect(state.isBlank == false)
    }

    // MARK: Freeze vs blank screens

    @Test func freezeDoesNotTurnOnOverABlankScreen() {
        var state = LiveOutputHoldState()
        state.setBlack(true)
        #expect(state.canFreeze == false)
        let rFreeze = state.toggleFreeze()
        #expect(rFreeze == false)
        state.setBlack(false)
        state.toggleWhite()
        let otherFreeze = state.toggleFreeze()
        #expect(otherFreeze == false)
    }

    @Test func aBlankScreenEndsFreeze() {
        var state = LiveOutputHoldState()
        state.toggleFreeze()
        state.toggleWhite()
        #expect(state.isFrozen == false)

        var other = LiveOutputHoldState()
        other.toggleFreeze()
        other.setBlack(true)
        #expect(other.isFrozen == false)
    }

    @Test func lockAndBlankScreensAreIndependent() {
        var state = LiveOutputHoldState()
        state.setLocked(true)
        state.toggleWhite()
        #expect(state.isLocked)
        #expect(state.isWhite)
    }

    // MARK: Show Live compatibility

    @Test func snapshotWithoutFreezeFieldsDecodesAsOff() throws {
        let showId = UUID()
        let json = """
        {"showId":"\(showId.uuidString)","isBlackout":false,"isLocked":false,\
        "directorName":"Old"}
        """
        let snap = try JSONDecoder().decode(ShowLiveSnapshot.self, from: Data(json.utf8))
        #expect(snap.isFrozen == nil)
        #expect(snap.isWhite == nil)
    }

    @Test func snapshotFreezeFieldsRoundTrip() throws {
        let snap = ShowLiveSnapshot(
            showId: UUID(), liveItemId: nil, liveKind: nil, isBlackout: false,
            isLocked: false, directorName: "Dir", isFrozen: true, isWhite: true
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(ShowLiveSnapshot.self, from: data)
        #expect(back.isFrozen == true)
        #expect(back.isWhite == true)
    }

    @Test func freezeChangeIsAProgramChange() {
        let off = ShowLiveSnapshot(
            showId: UUID(), liveItemId: nil, liveKind: nil, isBlackout: false,
            isLocked: false, directorName: "Dir"
        )
        var on = off
        on.isFrozen = true
        #expect(on.isSameProgram(as: off) == false)
        var offAgain = off
        offAgain.isFrozen = false
        #expect(offAgain.isSameProgram(as: off))
    }

    @Test func newVerbsRoundTripAndUnknownVerbsFailToDecode() throws {
        let command = ShowLiveCommand(verb: .freezeToggle, value: nil)
        let data = try JSONEncoder().encode(command)
        #expect(try JSONDecoder().decode(ShowLiveCommand.self, from: data) == command)
        // An older build receiving a verb it lacks fails decoding, which the session
        // drops (`try?`), never a crash.
        let future = Data(#"{"verb":"somethingNew"}"#.utf8)
        #expect((try? JSONDecoder().decode(ShowLiveCommand.self, from: future)) == nil)
    }
}
