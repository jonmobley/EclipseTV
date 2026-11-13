//
//  ShowLivePeerHandshake.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
import Foundation

/// Which side of a Show Live connection a phone is on.
enum ShowLivePeerRole: String, Codable, Equatable {
    case director = "d"
    case joiner = "j"
}

/// Wire message on the `eclipse-live` session. Builds before 2026-11-13 sent
/// bare `ShowLiveEnvelope`s, which are no longer accepted.
struct ShowLiveSecureMessage: Codable, Equatable {
    enum Kind: String, Codable {
        /// "Here is my role and my fresh nonce."
        case hello = "h"
        /// "I hold the account key": HMAC over both nonces, roles and names.
        case proof = "p"
        /// A `ShowLiveEnvelope`, encrypted and authenticated with a session key.
        case sealed = "s"
    }

    var kind: Kind
    var role: ShowLivePeerRole?
    var nonce: String?
    var proof: String?
    var box: Data?

    enum CodingKeys: String, CodingKey {
        case kind = "t", role = "r", nonce = "n", proof = "p", box = "b"
    }
}

/// Mutual check that runs once two phones are connected, then seals traffic.
///
/// The invitation proof alone can be relayed: a nearby device can pose as a
/// director to a real phone and pass that phone's invitation to the real
/// director. So after connecting, each side sends a fresh nonce, then an HMAC
/// over both nonces, both roles and both peer names, keyed by the account key.
/// A relay can pass these along but can't make them itself. Every message after
/// that is AES-GCM sealed with keys derived from the account key and both
/// nonces, one per direction, with a counter, so a relay can't read, change,
/// inject, replay or bounce back anything.
///
/// Thread safety: a value type; `ShowLiveSession` keeps one per peer on the
/// main actor.
struct ShowLivePeerHandshake {

    /// What to do with a peer's hello.
    enum HelloOutcome: Equatable {
        /// Send this proof back.
        case reply(ShowLiveSecureMessage)
        /// Another phone of the same role (operators see each other in the
        /// Multipeer mesh). Leave it alone; it is never trusted.
        case sameRole
        /// Malformed or repeated; disconnect the peer.
        case refused
    }

    let localRole: ShowLivePeerRole
    let localNonce: String
    private let localName: String
    private let peerName: String
    private let key: SymmetricKey
    private(set) var peerRole: ShowLivePeerRole?
    private var peerNonce: String?
    /// True once the peer proved it holds the account key.
    private(set) var isPeerVerified = false
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    // MARK: - Initialization

    /// - Parameters:
    ///   - localRole: This phone's side.
    ///   - localName: This phone's `MCPeerID.displayName`.
    ///   - peerName: The other phone's `MCPeerID.displayName` as seen here.
    ///   - key: ``ShowLiveInviteProof/key(forAccountSecret:)``.
    ///   - localNonce: Fresh random value; tests may pass a fixed one.
    init(
        localRole: ShowLivePeerRole, localName: String, peerName: String,
        key: SymmetricKey, localNonce: String = ShowLiveInviteProof.newChallenge()
    ) {
        self.localRole = localRole
        self.localName = localName
        self.peerName = peerName
        self.key = key
        self.localNonce = localNonce
    }

    // MARK: - Handshake

    /// First message to send once connected.
    var hello: ShowLiveSecureMessage {
        ShowLiveSecureMessage(kind: .hello, role: localRole, nonce: localNonce)
    }

    /// Handles the peer's hello.
    /// - Parameter message: A `.hello` message.
    /// - Returns: Whether to answer, ignore, or drop the peer.
    mutating func receiveHello(_ message: ShowLiveSecureMessage) -> HelloOutcome {
        guard message.kind == .hello, peerNonce == nil, let role = message.role,
              let nonce = message.nonce, ShowLiveInviteProof.isWellFormedNonce(nonce),
              nonce != localNonce
        else { return .refused }
        guard role != localRole else { return .sameRole }
        peerRole = role
        peerNonce = nonce
        let mac = HMAC<SHA256>.authenticationCode(for: transcript(prover: localRole), using: key)
        return .reply(ShowLiveSecureMessage(kind: .proof, proof: Data(mac).hexString))
    }

    /// Checks the peer's proof; on success the session keys are ready.
    /// - Parameter message: A `.proof` message.
    /// - Returns: True only for a correct proof after a hello.
    mutating func receiveProof(_ message: ShowLiveSecureMessage) -> Bool {
        guard message.kind == .proof, !isPeerVerified, let peerRole,
              let hex = message.proof, let given = Data(hex: hex),
              HMAC<SHA256>.isValidAuthenticationCode(
                given, authenticating: transcript(prover: peerRole), using: key
              )
        else { return false }
        isPeerVerified = true
        sendKey = directionKey(from: localRole)
        receiveKey = directionKey(from: peerRole)
        return true
    }

    // MARK: - Sealed traffic

    /// Encrypts one payload for the peer.
    /// - Parameter plaintext: Encoded `ShowLiveEnvelope`.
    /// - Returns: A `.sealed` message, or nil before the peer is verified.
    mutating func seal(_ plaintext: Data) -> ShowLiveSecureMessage? {
        guard isPeerVerified, let sendKey else { return nil }
        sendCounter += 1
        var payload = withUnsafeBytes(of: sendCounter.bigEndian) { Data($0) }
        payload.append(plaintext)
        guard let box = try? AES.GCM.seal(payload, using: sendKey).combined else { return nil }
        return ShowLiveSecureMessage(kind: .sealed, box: box)
    }

    /// Decrypts one payload from the peer.
    /// - Parameter message: A `.sealed` message.
    /// - Returns: The plaintext, or nil if unverified, tampered, replayed or
    ///   out of order.
    mutating func open(_ message: ShowLiveSecureMessage) -> Data? {
        guard message.kind == .sealed, isPeerVerified, let receiveKey,
              let combined = message.box,
              let box = try? AES.GCM.SealedBox(combined: combined),
              let payload = try? AES.GCM.open(box, using: receiveKey),
              payload.count >= Self.counterSize
        else { return nil }
        let counter = payload.prefix(Self.counterSize)
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard counter > receiveCounter else { return nil }
        receiveCounter = counter
        return Data(payload.dropFirst(Self.counterSize))
    }

    // MARK: - Private Helpers

    private static let counterSize = MemoryLayout<UInt64>.size

    /// Director values first, so both sides build the same bytes.
    private var orderedParts: [String] {
        let peerNonce = peerNonce ?? ""
        return localRole == .director
            ? [localNonce, peerNonce, localName, peerName]
            : [peerNonce, localNonce, peerName, localName]
    }

    private func transcript(prover: ShowLivePeerRole) -> Data {
        let parts = ["EclipseShowLive.auth.v1", prover.rawValue] + orderedParts
        return Data(parts.joined(separator: "|").utf8)
    }

    private func directionKey(from sender: ShowLivePeerRole) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: transcript(prover: sender),
            info: Data("EclipseShowLive.seal.\(sender.rawValue)".utf8),
            outputByteCount: 32
        )
    }
}
