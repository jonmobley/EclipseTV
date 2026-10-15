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

    private let key = String(repeating: "ab", count: 32)

    @Test func pinContextRoundTrips() {
        let data = PeerPairing.pinContext("042891", deviceKey: key)
        #expect(data != nil)
        #expect(PeerPairing.parse(data) == .pin("042891", deviceKey: key))
    }

    @Test func rememberedContextRoundTrips() {
        let data = PeerPairing.rememberedContext(deviceKey: key)
        #expect(data != nil)
        #expect(PeerPairing.parse(data) == .remembered(deviceKey: key))
    }

    @Test func rejectsOlderProtocols() {
        #expect(PeerPairing.parse("EclipseShare/v1-iPhone".data(using: .utf8)) == nil)
        // v2 trusted device names and carried no device key.
        #expect(PeerPairing.parse("EclipseShare/v2|remembered".data(using: .utf8)) == nil)
        #expect(PeerPairing.parse("EclipseShare/v2|123456".data(using: .utf8)) == nil)
    }

    @Test func rejectsMissingOrBadDeviceKey() {
        #expect(PeerPairing.parse("EclipseShare/v3|remembered".data(using: .utf8)) == nil)
        #expect(PeerPairing.parse("EclipseShare/v3|remembered|short".data(using: .utf8)) == nil)
        let upper = String(repeating: "AB", count: 32)
        #expect(PeerPairing.parse("EclipseShare/v3|remembered|\(upper)".data(using: .utf8)) == nil)
        #expect(PeerPairing.rememberedContext(deviceKey: "nope") == nil)
    }

    @Test func rejectsWrongPINLengthInContext() {
        let bad = "EclipseShare/v3|12345|\(key)".data(using: .utf8)
        #expect(PeerPairing.parse(bad) == nil)
    }

    @Test func generatedDeviceKeysAreValidAndDistinct() {
        let a = PeerPairing.generateDeviceKey()
        let b = PeerPairing.generateDeviceKey()
        #expect(PeerPairing.isValidDeviceKey(a))
        #expect(a != b)
    }

    @Test func pairedStoreTrustsDeviceKeyNotName() {
        let defaults = UserDefaults(suiteName: "PeerPairingTests.\(UUID().uuidString)")!
        let store = PairedPeerStore(defaults: defaults)
        store.remember(deviceKey: key, displayName: "iPhone")
        #expect(store.isPaired(deviceKey: key))
        #expect(!store.isPaired(deviceKey: PeerPairing.generateDeviceKey()))
        store.forgetAll()
        #expect(!store.isPaired(deviceKey: key))
    }

    @Test func wrongPINsRotateCodeAndPausePairing() {
        let defaults = UserDefaults(suiteName: "PeerPairingTests.\(UUID().uuidString)")!
        let store = PairedPeerStore(defaults: defaults)
        let original = store.currentPIN
        let wrong = original == "000000" ? "111111" : "000000"
        let start = Date()
        for attempt in 1..<PairedPeerStore.maxWrongPINAttempts {
            #expect(store.checkPIN(wrong, now: start) == (false, false), "attempt \(attempt)")
        }
        #expect(store.checkPIN(wrong, now: start) == (false, true))
        #expect(store.currentPIN != original)
        // Even the new code is refused during the pause, then accepted after it.
        #expect(store.checkPIN(store.currentPIN, now: start.addingTimeInterval(5)).accepted == false)
        let later = start.addingTimeInterval(PairedPeerStore.wrongPINLockout + 1)
        #expect(store.checkPIN(store.currentPIN, now: later).accepted)
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

    @Test func envelopeSetIdleModeRoundTrips() {
        let black = EclipseShareEnvelope.setIdleMode(black: true).encoded()
        #expect(black != nil)
        let blackDecoded = EclipseShareEnvelope.decode(from: black!)
        #expect(blackDecoded?.kind == .setIdleMode)
        #expect(blackDecoded?.mode == "black")

        let clear = EclipseShareEnvelope.setIdleMode(black: false).encoded()
        #expect(clear != nil)
        let clearDecoded = EclipseShareEnvelope.decode(from: clear!)
        #expect(clearDecoded?.kind == .setIdleMode)
        #expect(clearDecoded?.mode == "clear")
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
