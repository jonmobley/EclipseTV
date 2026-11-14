//
//  BlackoutHoldTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// Blackout holds the audience's screen while the phone stays usable.
struct BlackoutHoldTests {

    // MARK: Tile taps

    @Test func blackoutTurnsTapsIntoPreviewEvenWithADestination() {
        #expect(
            LiveOutputRouting.prefersPhonePreviewOnTap(
                isLiveOutputLocked: false,
                hasOutputDestination: true,
                isBlackoutHolding: true
            )
        )
    }

    @Test func withoutBlackoutTapsStillGoLive() {
        #expect(
            LiveOutputRouting.prefersPhonePreviewOnTap(
                isLiveOutputLocked: false,
                hasOutputDestination: true,
                isBlackoutHolding: false
            ) == false
        )
    }

    // MARK: Cue keys

    @Test func cueKeyMatchesTheSameSlideshowAcrossRebuilds() {
        let id = UUID()
        let a = Slideshow(id: id, showId: UUID(), name: "Intro", itemIds: ["x"])
        var b = a
        b.name = "Renamed"
        #expect(
            LibraryGridViewController.blackoutCueKey(for: .slideshow(a))
                == LibraryGridViewController.blackoutCueKey(for: .slideshow(b))
        )
    }

    @Test func cueKeysDifferAcrossKinds() {
        let page = WebPage(title: "Site", url: URL(string: "https://a.example")!)
        let show = Slideshow(id: page.id, showId: UUID(), name: "Same id", itemIds: [])
        #expect(
            LibraryGridViewController.blackoutCueKey(for: .website(page))
                != LibraryGridViewController.blackoutCueKey(for: .slideshow(show))
        )
    }

    @Test func onlyUnattendedTilesCanBeCued() {
        #expect(ShowGridItem.logo.canAutoPresentLive)
        #expect(ShowGridItem.camera.canAutoPresentLive == false)
        #expect(ShowGridItem.prompter.canAutoPresentLive == false)
    }

    @Test func cueTitlesNameTools() {
        #expect(LibraryGridViewController.blackoutCueTitle(for: .logo) == "Background")
        #expect(LibraryGridViewController.blackoutCueTitle(for: .screensaver) == "Screensaver")
        #expect(LibraryGridViewController.blackoutCueTitle(for: .camera) == nil)
    }

    // MARK: Apple TV message

    @Test func pausedPlayRequestCarriesTheFlag() throws {
        let envelope = EclipseShareEnvelope.playRequest(id: "a.mov", startAt: 12, startsPaused: true)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(envelope)
        ) as? [String: Any]
        #expect(json?["startsPaused"] as? Bool == true)
        #expect(json?["position"] as? Double == 12)
    }

    @Test func ordinaryPlayRequestLeavesTheFlagOff() throws {
        let envelope = EclipseShareEnvelope.playRequest(id: "a.mov")
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(envelope)
        ) as? [String: Any]
        #expect(json?["startsPaused"] == nil)
    }

    @Test func messagesFromOlderPhonesStillDecode() throws {
        let old = #"{"eclipseMsg":"play_request","id":"a.mov","position":3}"#
        let envelope = try JSONDecoder().decode(
            EclipseShareEnvelope.self, from: Data(old.utf8)
        )
        #expect(envelope.startsPaused == nil)
        #expect(envelope.position == 3)
    }
}
