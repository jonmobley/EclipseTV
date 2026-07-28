//
//  PeerPairingTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseAppleTV

struct PeerPairingTests {

    @Test func normalizeStripsNonDigits() {
        #expect(PeerPairing.normalizePIN("12 34-56") == "123456")
        #expect(PeerPairing.normalizePIN("abc") == "")
    }

    @Test func isValidPINRequiresSixDigits() {
        #expect(PeerPairing.isValidPIN("123456"))
        #expect(!PeerPairing.isValidPIN("12345"))
        #expect(!PeerPairing.isValidPIN("1234567"))
        #expect(!PeerPairing.isValidPIN("12ab56"))
    }

    @Test func pinContextRoundTrips() {
        let data = PeerPairing.pinContext("042891")
        #expect(data != nil)
        #expect(PeerPairing.parse(data) == .pin("042891"))
    }

    @Test func rememberedContextRoundTrips() {
        let data = PeerPairing.rememberedContext()
        #expect(data != nil)
        #expect(PeerPairing.parse(data) == .remembered)
    }

    @Test func rejectsLegacyV1Token() {
        let legacy = "EclipseShare/v1-iPhone".data(using: .utf8)
        #expect(PeerPairing.parse(legacy) == nil)
    }

    @Test func rejectsWrongPINLengthInContext() {
        let bad = "EclipseShare/v2|12345".data(using: .utf8)
        #expect(PeerPairing.parse(bad) == nil)
    }

    @Test func generatePINIsSixDigits() {
        let pin = PeerPairing.generatePIN()
        #expect(PeerPairing.isValidPIN(pin))
    }

    @Test func envelopeSetAccountRoundTrips() {
        let data = EclipseShareEnvelope.setAccount(code: "654321").encoded()
        #expect(data != nil)
        let decoded = EclipseShareEnvelope.decode(from: data!)
        #expect(decoded?.kind == .setAccount)
        #expect(decoded?.accountCode == "654321")
    }

    @Test func albumConfigNormalizeAndValidate() {
        #expect(AlbumConfig.normalize(" 12-34 56 ") == "123456")
        #expect(AlbumConfig.isValidCode("123456"))
        #expect(!AlbumConfig.isValidCode("12345"))
        let url = AlbumConfig.manifestURL(forCode: "123456")
        #expect(url?.absoluteString.contains("code=123456") == true)
    }

    @Test func receivedMediaKindFromExtension() {
        #expect(ReceivedMediaValidator.kind(forExtension: "jpg") == .image)
        #expect(ReceivedMediaValidator.kind(forExtension: "MP4") == .video)
        #expect(ReceivedMediaValidator.kind(forExtension: "exe") == nil)
    }

    @Test func mediaResourceNameRoundTripsWithMode() {
        let wire = EclipseShareProtocol.mediaResourceName(for: "clip.mp4", mode: .vertical)
        let parsed = EclipseShareProtocol.parseMediaResourceName(wire)
        #expect(parsed.fileName == "clip.mp4")
        #expect(parsed.mode == .vertical)

        let legacy = EclipseShareProtocol.parseMediaResourceName("photo.jpg")
        #expect(legacy.fileName == "photo.jpg")
        #expect(legacy.mode == nil)
    }

    @Test func libraryModeInferredFromPath() {
        #expect(
            EclipseShareProtocol.libraryMode(
                inferredFromPath: "/Caches/Media/Vertical/a.jpg"
            ) == .vertical
        )
        #expect(
            EclipseShareProtocol.libraryMode(
                inferredFromPath: "/Caches/Media/Landscape/a.jpg"
            ) == .landscape
        )
    }
}
