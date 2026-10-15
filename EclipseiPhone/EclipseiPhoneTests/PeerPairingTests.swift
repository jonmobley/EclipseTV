//
//  PeerPairingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseiPhone

struct PeerPairingTests {

    @Test func normalizeStripsNonDigits() {
        #expect(PeerPairing.normalizePIN("12 34-56") == "123456")
    }

    @Test func pinAndRememberedContextsParse() {
        let key = PeerPairing.generateDeviceKey()
        #expect(PeerPairing.parse(PeerPairing.pinContext("111222", deviceKey: key))
            == .pin("111222", deviceKey: key))
        #expect(PeerPairing.parse(PeerPairing.rememberedContext(deviceKey: key))
            == .remembered(deviceKey: key))
    }

    @Test func rejectsLegacyHandshake() {
        let legacy = "EclipseShare/v1-iPhone".data(using: .utf8)
        #expect(PeerPairing.parse(legacy) == nil)
        #expect(PeerPairing.parse("EclipseShare/v2|remembered".data(using: .utf8)) == nil)
    }

    @Test func deviceKeyIsStableAcrossCalls() {
        let first = iPhoneConnectionManager.pairingDeviceKey()
        #expect(PeerPairing.isValidDeviceKey(first))
        #expect(iPhoneConnectionManager.pairingDeviceKey() == first)
    }

    @Test func albumConfigSharedCore() {
        #expect(AlbumConfig.codeLength == 6)
        #expect(AlbumConfig.isValidCode(AlbumConfig.normalize("98 76 54")))
        #expect(AlbumConfig.manifestURL(forCode: "987654") != nil)
    }

    @Test func envelopePlayRequestRoundTrips() {
        let data = EclipseShareEnvelope.playRequest(id: "photo.jpg").encoded()
        let decoded = EclipseShareEnvelope.decode(from: data!)
        #expect(decoded?.kind == .playRequest)
        #expect(decoded?.id == "photo.jpg")
    }

    @Test func envelopeSetIdleModeRoundTrips() {
        let black = EclipseShareEnvelope.setIdleMode(black: true).encoded()
        let blackDecoded = EclipseShareEnvelope.decode(from: black!)
        #expect(blackDecoded?.kind == .setIdleMode)
        #expect(blackDecoded?.mode == "black")

        let clear = EclipseShareEnvelope.setIdleMode(black: false).encoded()
        let clearDecoded = EclipseShareEnvelope.decode(from: clear!)
        #expect(clearDecoded?.kind == .setIdleMode)
        #expect(clearDecoded?.mode == "clear")
    }

    @Test func mediaResourceNameRoundTripsWithMode() {
        let wire = EclipseShareProtocol.mediaResourceName(
            for: "thumbnail_clip.mp4", mode: .landscape
        )
        let parsed = EclipseShareProtocol.parseMediaResourceName(wire)
        #expect(parsed.fileName == "thumbnail_clip.mp4")
        #expect(parsed.mode == .landscape)
    }
}
