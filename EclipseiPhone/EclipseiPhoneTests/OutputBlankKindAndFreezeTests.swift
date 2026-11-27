//
//  OutputBlankKindAndFreezeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Blackout's White and Freeze, as on the Mac: words, wire shape, badges.
@MainActor
struct OutputBlankKindAndFreezeTests {

    @Test func blankKindWordsMatchTheMac() {
        #expect(OutputBlankKind.black.badgeText == "BLACK SCREEN")
        #expect(OutputBlankKind.white.badgeText == "WHITE SCREEN")
        #expect(OutputBlankKind.white.screenName == "White Screen")
    }

    /// Older Apple TVs read only `mode`, so White must still say "black".
    @Test func whiteParkStillSaysBlackForOlderTVs() throws {
        let envelope = EclipseShareEnvelope.setIdleMode(black: true, color: "white")
        #expect(envelope.mode == "black")
        #expect(envelope.color == "white")
        let cleared = EclipseShareEnvelope.setIdleMode(black: false, color: "white")
        #expect(cleared.mode == "clear")
        #expect(cleared.color == nil)
    }

    /// A snapshot from a build before Freeze / White still decodes.
    @Test func legacySnapshotDecodesWithoutFreezeOrColour() throws {
        let legacy = """
        {"showId":"\(UUID().uuidString)","isBlackout":true,"isLocked":false,"directorName":"Stage"}
        """
        let snap = try JSONDecoder().decode(ShowLiveSnapshot.self, from: Data(legacy.utf8))
        #expect(snap.isFrozen == nil)
        #expect(snap.blankKind == nil)
    }

    @Test func snapshotCarriesFreezeAndColour() throws {
        let sent = ShowLiveSnapshot(
            showId: UUID(), liveItemId: nil, liveKind: .black,
            isBlackout: true, isLocked: true, directorName: "Stage",
            isFrozen: true, blankKind: .white
        )
        let data = try JSONEncoder().encode(sent)
        let received = try JSONDecoder().decode(ShowLiveSnapshot.self, from: data)
        #expect(received == sent)
        var changed = sent
        changed.blankKind = .black
        #expect(!changed.isSameProgram(as: sent))
    }

    @Test func whiteOverlayUsesDarkInk() {
        #expect(LiveHeaderView.overlayInk(on: .white) == .black)
        #expect(LiveHeaderView.overlayInk(on: .black) == .white)
    }
}
