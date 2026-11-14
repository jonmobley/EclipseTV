//
//  ShowLivePeerHandshakeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
import Foundation
import Testing
@testable import EclipseiPhone

/// After two phones connect, each must prove the account key, and a nearby
/// device that relays or copies traffic must not be able to read, inject,
/// replay or bounce back commands.
struct ShowLivePeerHandshakeTests {

    private let ownKey = ShowLiveInviteProof.key(forAccountSecret: Data(repeating: 7, count: 32))
    private let otherKey = ShowLiveInviteProof.key(forAccountSecret: Data(repeating: 9, count: 32))

    private func pair(
        directorKey: SymmetricKey? = nil, joinerKey: SymmetricKey? = nil
    ) -> (ShowLivePeerHandshake, ShowLivePeerHandshake) {
        let director = ShowLivePeerHandshake(
            localRole: .director, localName: "Stage iPhone", peerName: "Pocket iPhone",
            key: directorKey ?? ownKey
        )
        let joiner = ShowLivePeerHandshake(
            localRole: .joiner, localName: "Pocket iPhone", peerName: "Stage iPhone",
            key: joinerKey ?? ownKey
        )
        return (director, joiner)
    }

    /// Runs hello + proof both ways; returns whether each side verified the other.
    private func run(
        _ director: inout ShowLivePeerHandshake, _ joiner: inout ShowLivePeerHandshake
    ) -> (directorOK: Bool, joinerOK: Bool) {
        guard case .reply(let directorProof) = director.receiveHello(joiner.hello),
              case .reply(let joinerProof) = joiner.receiveHello(director.hello)
        else { return (false, false) }
        return (director.receiveProof(joinerProof), joiner.receiveProof(directorProof))
    }

    @Test func sameAccountPhonesVerifyEachOther() {
        var (director, joiner) = pair()
        let result = run(&director, &joiner)
        #expect(result.directorOK && result.joinerOK)
    }

    @Test func otherAccountIsRefusedBothWays() {
        var (director, joiner) = pair(joinerKey: otherKey)
        let result = run(&director, &joiner)
        #expect(!result.directorOK)
        #expect(!result.joinerOK)
    }

    @Test func sealedEnvelopeRoundTrips() throws {
        var (director, joiner) = pair()
        _ = run(&director, &joiner)
        let envelope = ShowLiveEnvelope(kind: .command, command: ShowLiveCommand(verb: .lockToggle))
        let maybeSealed = joiner.seal(try JSONEncoder().encode(envelope))
        let sealed = try #require(maybeSealed)
        let maybeOpened = director.open(sealed)
        let opened = try #require(maybeOpened)
        #expect(try JSONDecoder().decode(ShowLiveEnvelope.self, from: opened) == envelope)
    }

    @Test func nothingIsSealedOrOpenedBeforeVerification() {
        var (director, joiner) = pair()
        let early = joiner.seal(Data("x".utf8))
        #expect(early == nil)
        let forged = ShowLiveSecureMessage(kind: .sealed, box: Data(repeating: 0, count: 64))
        let opened = director.open(forged)
        #expect(opened == nil)
    }

    @Test func relayCannotInjectWithoutTheKey() throws {
        var (director, joiner) = pair()
        _ = run(&director, &joiner)
        // The relay saw every handshake message but not the key.
        var relay = ShowLivePeerHandshake(
            localRole: .joiner, localName: "Pocket iPhone", peerName: "Stage iPhone", key: otherKey
        )
        _ = relay.receiveHello(director.hello)
        let relayVerified = relay.receiveProof(ShowLiveSecureMessage(kind: .proof, proof: "00"))
        #expect(!relayVerified)
        let injected = relay.seal(Data("x".utf8))
        #expect(injected == nil)
        let maybeReal = joiner.seal(Data("lock".utf8))
        let real = try #require(maybeReal)
        var bytes = try #require(real.box)
        bytes[bytes.count - 1] ^= 0xFF
        let tamperedOpen = director.open(ShowLiveSecureMessage(kind: .sealed, box: bytes))
        #expect(tamperedOpen == nil)
    }

    @Test func replayedAndReflectedMessagesAreDropped() throws {
        var (director, joiner) = pair()
        _ = run(&director, &joiner)
        let maybeFirst = joiner.seal(Data("one".utf8))
        let first = try #require(maybeFirst)
        let openedOnce = director.open(first)
        let openedTwice = director.open(first)
        #expect(openedOnce != nil)
        #expect(openedTwice == nil)
        // The director's own message bounced back to it must not open.
        let maybeOwn = director.seal(Data("state".utf8))
        let own = try #require(maybeOwn)
        let bounced = director.open(own)
        let delivered = joiner.open(own)
        #expect(bounced == nil)
        #expect(delivered == Data("state".utf8))
    }

    @Test func proofIsBoundToPeerNames() {
        var director = ShowLivePeerHandshake(
            localRole: .director, localName: "Stage iPhone", peerName: "Relay", key: ownKey
        )
        var joiner = ShowLivePeerHandshake(
            localRole: .joiner, localName: "Pocket iPhone", peerName: "Stage iPhone", key: ownKey
        )
        let result = run(&director, &joiner)
        #expect(!result.directorOK)
        #expect(!result.joinerOK)
    }

    @Test func reflectedProofIsRefused() {
        var (director, _) = pair()
        let joinerHello = ShowLiveSecureMessage(
            kind: .hello, role: .joiner, nonce: ShowLiveInviteProof.newChallenge()
        )
        guard case .reply(let ownProof) = director.receiveHello(joinerHello) else {
            Issue.record("expected a proof")
            return
        }
        let accepted = director.receiveProof(ownProof)
        #expect(!accepted)
    }

    @Test func twoOperatorsIgnoreEachOther() {
        var first = ShowLivePeerHandshake(localRole: .joiner, localName: "A", peerName: "B", key: ownKey)
        let second = ShowLivePeerHandshake(localRole: .joiner, localName: "B", peerName: "A", key: ownKey)
        let outcome = first.receiveHello(second.hello)
        let sealed = first.seal(Data("x".utf8))
        #expect(outcome == .sameRole)
        #expect(sealed == nil)
    }

    @Test func malformedOrRepeatedHelloIsRefused() {
        var (director, joiner) = pair()
        let badNonce = director.receiveHello(ShowLiveSecureMessage(kind: .hello, role: .joiner, nonce: "zz"))
        let noRole = director.receiveHello(ShowLiveSecureMessage(kind: .hello, nonce: joiner.localNonce))
        #expect(badNonce == .refused)
        #expect(noRole == .refused)
        guard case .reply = director.receiveHello(joiner.hello) else {
            Issue.record("expected a proof")
            return
        }
        let repeated = director.receiveHello(joiner.hello)
        #expect(repeated == .refused)
    }
}

/// The account secret is made once, then reused; an unavailable Keychain keeps
/// Show Live off instead of falling back to a weaker key.
struct ShowLiveAccountSecretTests {

    private final class MemoryStore: ShowLiveSecretStore {
        var stored: ShowLiveSecretRead
        var addStatus: OSStatus
        init(_ stored: ShowLiveSecretRead, addStatus: OSStatus = errSecSuccess) {
            self.stored = stored
            self.addStatus = addStatus
        }
        func read() -> ShowLiveSecretRead { stored }
        func add(_ secret: Data) -> OSStatus {
            if addStatus == errSecSuccess { stored = .found(secret) }
            return addStatus
        }
    }

    @Test func createsOnceThenReuses() throws {
        let store = MemoryStore(.missing)
        let first = try #require(ShowLiveAccountSecret.loadOrCreate(store: store))
        #expect(first.count == ShowLiveAccountSecret.byteCount)
        #expect(ShowLiveAccountSecret.loadOrCreate(store: store) == first)
    }

    @Test func unavailableKeychainGivesNoKey() {
        #expect(ShowLiveAccountSecret.loadOrCreate(store: MemoryStore(.unavailable)) == nil)
        let failing = MemoryStore(.missing, addStatus: errSecInteractionNotAllowed)
        #expect(ShowLiveAccountSecret.loadOrCreate(store: failing) == nil)
    }

    @Test func wrongSizedSecretIsNotUsed() {
        #expect(ShowLiveAccountSecret.loadOrCreate(store: MemoryStore(.found(Data([1, 2])))) == nil)
    }

    @Test func differentSecretsGiveDifferentKeys() {
        let first = ShowLiveInviteProof.key(forAccountSecret: Data(repeating: 1, count: 32))
        let second = ShowLiveInviteProof.key(forAccountSecret: Data(repeating: 2, count: 32))
        #expect(first != second)
    }
}
