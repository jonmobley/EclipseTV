//
//  ShowKeyMapTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct ShowKeyMapTests {

    private let open = ShowKeyContext(
        isShowOpen: true, isKeyboardOwnedElsewhere: false, isBlackoutHolding: false
    )

    @Test func clickerKeysStepCards() {
        for key in [ShowKeyMap.rightArrow, ShowKeyMap.downArrow, ShowKeyMap.pageDown, " "] {
            #expect(ShowKeyMap.action(forInput: key, in: open) == .nextCard)
        }
        for key in [ShowKeyMap.leftArrow, ShowKeyMap.upArrow, ShowKeyMap.pageUp] {
            #expect(ShowKeyMap.action(forInput: key, in: open) == .previousCard)
        }
    }

    @Test func blackoutAndLockLetters() {
        #expect(ShowKeyMap.action(forInput: "b", in: open) == .toggleBlackout)
        #expect(ShowKeyMap.action(forInput: "B", in: open) == .toggleBlackout)
        #expect(ShowKeyMap.action(forInput: ".", in: open) == .toggleBlackout)
        #expect(ShowKeyMap.action(forInput: "l", in: open) == .toggleLock)
    }

    @Test func escapeOnlyClaimedWhileBlackoutHolds() {
        #expect(ShowKeyMap.action(forInput: ShowKeyMap.escape, in: open) == nil)
        var holding = open
        holding.isBlackoutHolding = true
        #expect(ShowKeyMap.action(forInput: ShowKeyMap.escape, in: holding) == .leaveBlackout)
    }

    @Test func stepsAside() {
        var home = open
        home.isShowOpen = false
        var typing = open
        typing.isKeyboardOwnedElsewhere = true
        #expect(ShowKeyMap.activeBindings(in: home).isEmpty)
        #expect(ShowKeyMap.activeBindings(in: typing).isEmpty)
        #expect(ShowKeyMap.action(forInput: " ", in: typing) == nil)
    }

    @Test func unknownKeysAreIgnored() {
        #expect(ShowKeyMap.action(forInput: "x", in: open) == nil)
        #expect(ShowKeyMap.action(forInput: "1", in: open) == nil)
    }
}
