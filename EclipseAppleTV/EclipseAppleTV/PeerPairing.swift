//
//  PeerPairing.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Security

/// Invitation-context format for Multipeer pairing between the Apple TV and iPhone.
///
/// IMPORTANT: Duplicated in the iPhone target
/// (`EclipseiPhone/EclipseiPhone/PeerPairing.swift`). Keep the code bodies in sync
/// (see `Scripts/verify_shared_sources.sh`).
///
/// Context strings:
/// - `EclipseShare/v2|<6-digit PIN>` — first-time pair using the code shown on the TV
/// - `EclipseShare/v2|remembered` — reconnect for a previously paired peer
enum PeerPairing {

    /// Wire prefix. Bumping this rejects older clients that only know `EclipseShare/v1`.
    static let protocolPrefix = "EclipseShare/v2"

    /// Digits in the on-screen pairing PIN.
    static let pinLength = 6

    /// Parsed invitation context from a Multipeer invite.
    enum Context: Equatable {
        case pin(String)
        case remembered
    }

    /// Builds invitation context for a first-time pair with the TV-displayed `pin`.
    static func pinContext(_ pin: String) -> Data? {
        let normalized = normalizePIN(pin)
        guard isValidPIN(normalized) else { return nil }
        return "\(protocolPrefix)|\(normalized)".data(using: .utf8)
    }

    /// Builds invitation context for a peer the TV has already allowlisted.
    static func rememberedContext() -> Data? {
        "\(protocolPrefix)|remembered".data(using: .utf8)
    }

    /// Parses Multipeer invitation `context`, or `nil` when malformed / wrong version.
    static func parse(_ context: Data?) -> Context? {
        guard let context,
              let string = String(data: context, encoding: .utf8) else { return nil }
        let parts = string.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == protocolPrefix else { return nil }
        let payload = String(parts[1])
        if payload == "remembered" { return .remembered }
        let pin = normalizePIN(payload)
        guard isValidPIN(pin) else { return nil }
        return .pin(pin)
    }

    /// Keeps digits only so spaces/dashes a user types are ignored.
    static func normalizePIN(_ raw: String) -> String {
        raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Whether `pin` is exactly `pinLength` digits (assumes already normalized).
    static func isValidPIN(_ pin: String) -> Bool {
        pin.count == pinLength && pin.allSatisfy(\.isNumber)
    }

    /// Cryptographically random 6-digit PIN (leading zeros allowed).
    static func generatePIN() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.withUnsafeBytes { $0.load(as: UInt32.self) } % 1_000_000
        return String(format: "%06d", value)
    }
}
