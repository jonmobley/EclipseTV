//
//  ShowLiveProtocolTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// The `eclipse-live` envelope crosses devices that may run different builds,
/// so the JSON shape is a contract, not an implementation detail.
struct ShowLiveProtocolTests {

    @Test func selectEnvelopeRoundTrips() throws {
        let sent = ShowLiveEnvelope(
            kind: .select, itemKind: .media, itemId: "abc", snapshot: nil
        )
        let data = try JSONEncoder().encode(sent)
        let received = try JSONDecoder().decode(ShowLiveEnvelope.self, from: data)
        #expect(received == sent)
    }

    @Test func stateEnvelopeRoundTripsWithSnapshot() throws {
        let snap = ShowLiveSnapshot(
            showId: UUID(), liveItemId: nil, liveKind: .black,
            isBlackout: true, isLocked: true, directorName: "Stage iPhone"
        )
        let sent = ShowLiveEnvelope(
            kind: .state, itemKind: nil, itemId: nil, snapshot: snap
        )
        let data = try JSONEncoder().encode(sent)
        let received = try JSONDecoder().decode(ShowLiveEnvelope.self, from: data)
        #expect(received.snapshot == snap)
        #expect(received.snapshot?.isBlackout == true)
    }

    @Test func itemKindWireValuesAreStable() {
        let expected: [ShowLiveItemKind: String] = [
            .media: "media", .web: "web", .pdf: "pdf", .camera: "camera",
            .countdown: "countdown", .slideshow: "slideshow", .logo: "logo",
            .screensaver: "screensaver", .livePoll: "livePoll", .black: "black"
        ]
        for (kind, raw) in expected {
            #expect(kind.rawValue == raw)
            #expect(ShowLiveItemKind(rawValue: raw) == kind)
        }
    }

    @Test func invitationUsesCompactKeys() throws {
        let invite = ShowLiveInvitation(showId: UUID(), userHash: "0011223344556677")
        let data = try JSONEncoder().encode(invite)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["s"] as? String == invite.showId.uuidString)
        #expect(object?["u"] as? String == invite.userHash)
        #expect(object?.count == 2)
    }

    @Test func commandEnvelopeRoundTrips() throws {
        let sent = ShowLiveEnvelope(
            kind: .command,
            command: ShowLiveCommand(verb: .videoSeek, value: 42.5)
        )
        let data = try JSONEncoder().encode(sent)
        let received = try JSONDecoder().decode(ShowLiveEnvelope.self, from: data)
        #expect(received == sent)
        #expect(received.command?.verb == .videoSeek)
        #expect(received.command?.value == 42.5)
    }

    @Test func commandVerbWireValuesAreStable() {
        let expected: [ShowLiveCommandVerb: String] = [
            .videoToggle: "videoToggle", .videoSkip: "videoSkip",
            .videoSeek: "videoSeek", .countdownToggleRunning: "countdownToggleRunning",
            .countdownReset: "countdownReset",
            .countdownSetDuration: "countdownSetDuration", .lockToggle: "lockToggle"
        ]
        for (verb, raw) in expected {
            #expect(verb.rawValue == raw)
            #expect(ShowLiveCommandVerb(rawValue: raw) == verb)
        }
    }

    @Test func legacySnapshotWithoutTransportStateDecodes() throws {
        let showId = UUID()
        let json = """
        {"kind":"state","snapshot":{"showId":"\(showId.uuidString)",
        "liveKind":"media","liveItemId":"m1","isBlackout":false,
        "isLocked":false,"directorName":"Old build"}}
        """
        let received = try JSONDecoder().decode(
            ShowLiveEnvelope.self, from: Data(json.utf8)
        )
        #expect(received.snapshot?.video == nil)
        #expect(received.snapshot?.countdown == nil)
        #expect(received.command == nil)
    }

    @Test func tickOnlyChangesKeepTheSameProgram() {
        let showId = UUID()
        let first = ShowLiveSnapshot(
            showId: showId, liveItemId: "v1", liveKind: .media,
            isBlackout: false, isLocked: false, directorName: "A",
            video: ShowLiveVideoState(isPlaying: true, currentTime: 3, duration: 90)
        )
        var tick = first
        tick.video?.currentTime = 4
        #expect(tick.isSameProgram(as: first))
        #expect(tick != first)

        var locked = first
        locked.isLocked = true
        #expect(locked.isSameProgram(as: first) == false)

        var other = first
        other.liveItemId = "v2"
        #expect(other.isSameProgram(as: first) == false)
        #expect(first.isSameProgram(as: nil) == false)
    }

    @Test func unknownItemKindIsRejectedNotCrashed() {
        let json = #"{"kind":"select","itemKind":"hologram","itemId":"x"}"#
        let decoded = try? JSONDecoder().decode(
            ShowLiveEnvelope.self, from: Data(json.utf8)
        )
        #expect(decoded == nil)
    }
}
