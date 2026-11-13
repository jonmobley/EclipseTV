//
//  ShowLiveInviteProof.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
import Foundation

/// Proves a joining phone is signed in to the same iCloud account as the
/// director, without sending anything a nearby device could copy.
///
/// The director advertises the Show id and a short hash of the iCloud user
/// record name, which anyone nearby can read. Matching those alone let any
/// device join and send commands (AUDIT_2026-11-02 P-3). Now the director also
/// advertises a fresh random challenge, and the joiner answers with an HMAC of
/// it keyed by the record name itself, which never leaves the account's
/// devices. Each invitation also carries the joiner's own random nonce inside
/// the HMAC, and the director accepts each nonce once, so a copied invitation
/// cannot be sent again. Pure functions so tests need no Multipeer.
enum ShowLiveInviteProof {

    /// Key both phones derive from the iCloud user record name.
    /// - Parameter recordName: `CKRecord.ID.recordName` of the current user.
    /// - Returns: A key that stays in memory only.
    static func key(forRecordName recordName: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data("EclipseShowLive.v1|\(recordName)".utf8))
        return SymmetricKey(data: Data(digest))
    }

    /// A new random challenge for one advertising run.
    /// - Returns: 32 hex characters (128 bits).
    static func newChallenge() -> String {
        let bytes = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The joiner's answer to a challenge for one Show.
    /// - Parameters:
    ///   - challenge: Value from the director's discovery info.
    ///   - showId: Show both phones have open.
    ///   - nonce: The joiner's fresh ``newChallenge()`` for this invitation.
    ///   - key: ``key(forRecordName:)``.
    /// - Returns: Hex HMAC-SHA256.
    static func answer(challenge: String, showId: UUID, nonce: String, key: SymmetricKey) -> String {
        let message = signedMessage(challenge: challenge, showId: showId, nonce: nonce)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether an invitation's answer matches this director's challenge.
    /// - Parameters:
    ///   - proof: Answer from the invitation, if any.
    ///   - challenge: The challenge this director is advertising.
    ///   - showId: The director's open Show.
    ///   - nonce: Nonce from the invitation, if any.
    ///   - key: The director's own ``key(forRecordName:)``.
    /// - Returns: True only for a correct answer; compared in constant time.
    static func isValid(
        proof: String?, challenge: String, showId: UUID, nonce: String?, key: SymmetricKey
    ) -> Bool {
        guard let proof, let nonce, !nonce.isEmpty, let given = Data(hex: proof) else { return false }
        let message = signedMessage(challenge: challenge, showId: showId, nonce: nonce)
        return HMAC<SHA256>.isValidAuthenticationCode(given, authenticating: message, using: key)
    }

    /// Whether a nonce has the shape ``newChallenge()`` makes: 32 hex digits.
    /// - Parameter nonce: Value from an invitation.
    /// - Returns: False for anything else, before any other work.
    static func isWellFormedNonce(_ nonce: String) -> Bool {
        nonce.count == nonceLength && nonce.allSatisfy(\.isHexDigit)
    }

    private static let nonceLength = 32

    private static func signedMessage(challenge: String, showId: UUID, nonce: String) -> Data {
        Data("\(showId.uuidString)|\(challenge)|\(nonce)".utf8)
    }
}

// MARK: - Hex

private extension Data {
    /// Decodes lowercase or uppercase hex; nil for odd length or a bad digit.
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
