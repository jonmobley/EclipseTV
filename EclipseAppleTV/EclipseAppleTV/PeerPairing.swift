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
/// Context strings (the device key is a random secret each iPhone keeps in its Keychain;
/// the TV remembers paired phones by it, because iOS 16+ reports every device name as
/// just "iPhone"):
/// - `EclipseShare/v3|<6-digit PIN>|<device key>` — first-time pair using the code shown on the TV
/// - `EclipseShare/v3|remembered|<device key>` — reconnect for a previously paired phone
enum PeerPairing {

    /// Wire prefix. Bumping this rejects older clients (v2 trusted device names).
    static let protocolPrefix = "EclipseShare/v3"

    /// Digits in the on-screen pairing PIN.
    static let pinLength = 6

    /// Hex characters in a device key (32 random bytes).
    static let deviceKeyLength = 64

    /// Parsed invitation context from a Multipeer invite.
    enum Context: Equatable {
        case pin(String, deviceKey: String)
        case remembered(deviceKey: String)

        var deviceKey: String {
            switch self {
            case .pin(_, let key), .remembered(let key): return key
            }
        }
    }

    /// Builds invitation context for a first-time pair with the TV-displayed `pin`.
    static func pinContext(_ pin: String, deviceKey: String) -> Data? {
        let normalized = normalizePIN(pin)
        guard isValidPIN(normalized), isValidDeviceKey(deviceKey) else { return nil }
        return "\(protocolPrefix)|\(normalized)|\(deviceKey)".data(using: .utf8)
    }

    /// Builds invitation context for a phone the TV has already paired with.
    static func rememberedContext(deviceKey: String) -> Data? {
        guard isValidDeviceKey(deviceKey) else { return nil }
        return "\(protocolPrefix)|remembered|\(deviceKey)".data(using: .utf8)
    }

    /// Parses Multipeer invitation `context`, or `nil` when malformed / wrong version.
    static func parse(_ context: Data?) -> Context? {
        guard let context,
              let string = String(data: context, encoding: .utf8) else { return nil }
        let parts = string.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == protocolPrefix else { return nil }
        let deviceKey = String(parts[2])
        guard isValidDeviceKey(deviceKey) else { return nil }
        let payload = String(parts[1])
        if payload == "remembered" { return .remembered(deviceKey: deviceKey) }
        let pin = normalizePIN(payload)
        guard isValidPIN(pin) else { return nil }
        return .pin(pin, deviceKey: deviceKey)
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

    /// Whether `key` is `deviceKeyLength` lowercase hex characters.
    static func isValidDeviceKey(_ key: String) -> Bool {
        key.count == deviceKeyLength && key.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Cryptographically random 6-digit PIN (leading zeros allowed).
    static func generatePIN() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.withUnsafeBytes { $0.load(as: UInt32.self) } % 1_000_000
        return String(format: "%06d", value)
    }

    /// Cryptographically random device key (32 bytes as lowercase hex).
    static func generateDeviceKey() -> String {
        var bytes = [UInt8](repeating: 0, count: deviceKeyLength / 2)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
