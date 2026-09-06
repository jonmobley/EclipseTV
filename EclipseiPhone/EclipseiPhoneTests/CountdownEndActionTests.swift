//
//  CountdownEndActionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CountdownEndActionTests {

    // MARK: - Tokens

    @Test func tokensRoundTrip() {
        for action in CountdownEndAction.allCases {
            #expect(CountdownEndAction(token: action.token) == action)
        }
    }

    @Test func unrecognizedTokenFallsBackToHold() {
        #expect(CountdownEndAction(token: nil) == .hold)
        #expect(CountdownEndAction(token: "") == .hold)
        #expect(CountdownEndAction(token: "startNextShow") == .hold)
        #expect(CountdownEndAction.fallback == .hold)
    }

    @Test func onlyArmedEndingsShowATileHint() {
        #expect(CountdownEndAction.hold.tileHint == nil)
        #expect(CountdownEndAction.black.tileHint == "Then black")
        #expect(CountdownEndAction.next.tileHint == "Then next")
    }

    // MARK: - Persistence

    @Test func countdownSavedBeforeEndActionsExistedDecodesAsHold() throws {
        let json = """
        {"id":"\(UUID().uuidString)","showId":"\(UUID().uuidString)",
         "name":"Pre-Service","duration":300,"createdAt":0}
        """
        let item = try JSONDecoder().decode(
            ShowCountdown.self,
            from: Data(json.utf8)
        )
        #expect(item.endAction == .hold)
    }

    @Test func endActionSurvivesEncodeAndDecode() throws {
        let item = ShowCountdown(
            showId: UUID(),
            name: "Pre-Service",
            duration: 300,
            endAction: .next
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ShowCountdown.self, from: data)
        #expect(decoded.endAction == .next)
        #expect(decoded == item)
    }

    @Test func unreadableStoredTokenDegradesWithoutFailingTheDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","showId":"\(UUID().uuidString)",
         "name":"Pre-Service","duration":300,"endAction":"teleport","createdAt":0}
        """
        let item = try JSONDecoder().decode(
            ShowCountdown.self,
            from: Data(json.utf8)
        )
        #expect(item.endAction == .hold)
        #expect(item.name == "Pre-Service")
    }

    // MARK: - Next Item

    @Test func nextItemSkipsTilesThatNeedAPerson() {
        let showId = UUID()
        let target = ShowCountdown(showId: showId, name: "Pre-Service", duration: 300)
        let later = ShowCountdown(showId: showId, name: "Offering", duration: 60)
        let items: [ShowGridItem] = [
            .logo,
            .countdown(target),
            .camera,
            .countdown(later),
            .screensaver
        ]
        #expect(
            LibraryGridViewController.itemAfterCountdown(target.id, in: items)
                == .screensaver
        )
    }

    @Test func nextItemIsNilWhenTheShowEndsOnTheCountdown() {
        let target = ShowCountdown(showId: UUID(), name: "Closer", duration: 300)
        let items: [ShowGridItem] = [
            .screensaver,
            .countdown(target),
            .camera,
            .unresolved(id: "pending"),
            .add
        ]
        #expect(LibraryGridViewController.itemAfterCountdown(target.id, in: items) == nil)
    }

    @Test func nextItemIsNilWhenTheCountdownIsNotInTheShow() {
        let items: [ShowGridItem] = [.logo, .screensaver]
        #expect(LibraryGridViewController.itemAfterCountdown(UUID(), in: items) == nil)
    }

    @Test func autoPresentableTilesAreTheOnesThatNeedNobody() {
        #expect(ShowGridItem.screensaver.canAutoPresentLive)
        #expect(ShowGridItem.logo.canAutoPresentLive)
        #expect(ShowGridItem.camera.canAutoPresentLive == false)
        #expect(ShowGridItem.add.canAutoPresentLive == false)
        #expect(ShowGridItem.unresolved(id: "pending").canAutoPresentLive == false)
        let countdown = ShowCountdown(showId: UUID(), name: "Next", duration: 60)
        #expect(ShowGridItem.countdown(countdown).canAutoPresentLive == false)
    }
}
