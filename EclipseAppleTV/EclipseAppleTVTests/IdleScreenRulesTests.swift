//
//  IdleScreenRulesTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseAppleTV

/// When the calm idle screen shows, and what remote presses do on it.
struct IdleScreenRulesTests {

    /// A TV that is ready and waiting.
    private static let ready = IdleScreenContext(
        isInGridMode: true, isShowingPairingScreen: false, hasPairedPhone: true,
        isMoveMode: false, isMenuOpen: false, isParked: false, isBrowsingLibrary: false
    )

    @Test func showsWhenReadyAndWaiting() {
        #expect(IdleScreenRules.shouldShow(Self.ready))
    }

    @Test func neverHidesFirstTimeSetup() {
        var notPaired = Self.ready
        notPaired.hasPairedPhone = false
        #expect(!IdleScreenRules.shouldShow(notPaired))
        var pairingScreen = Self.ready
        pairingScreen.isShowingPairingScreen = true
        #expect(!IdleScreenRules.shouldShow(pairingScreen))
    }

    @Test func staysAwayWhileSomethingElseOwnsTheScreen() {
        var fullScreen = Self.ready
        fullScreen.isInGridMode = false
        var moving = Self.ready
        moving.isMoveMode = true
        var menu = Self.ready
        menu.isMenuOpen = true
        var parked = Self.ready
        parked.isParked = true
        var browsing = Self.ready
        browsing.isBrowsingLibrary = true
        for context in [fullScreen, moving, menu, parked, browsing] {
            #expect(!IdleScreenRules.shouldShow(context))
        }
    }

    @Test func pressesShowTheHintOrOpenTheLibrary() {
        #expect(IdleScreenRules.action(for: .arrow) == .showHint)
        #expect(IdleScreenRules.action(for: .other) == .showHint)
        #expect(IdleScreenRules.action(for: .select) == .browseLibrary)
        #expect(IdleScreenRules.action(for: .playPause) == .browseLibrary)
        #expect(IdleScreenRules.action(for: .menu) == .passThrough)
    }

    @Test func hintFadesAfterAFewSeconds() {
        #expect(IdleScreenRules.hintVisibleSeconds >= 3)
        #expect(IdleScreenRules.hintVisibleSeconds <= 10)
    }
}
