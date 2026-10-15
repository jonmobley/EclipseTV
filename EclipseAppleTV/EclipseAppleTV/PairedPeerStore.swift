//
//  PairedPeerStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
import Foundation
import os.log

/// Allowlist of iPhone companions that have successfully paired with this Apple TV.
///
/// Phones are keyed by the random device key each iPhone sends in its invitation context
/// (see `PeerPairing`), stored here only as a SHA-256 hash. Device names are kept for
/// display only: since iOS 16 every iPhone reports its name as just "iPhone", so a name
/// can't prove which phone is asking. A correct pairing PIN is required on first connect.
final class PairedPeerStore {

    static let shared = PairedPeerStore()

    /// Wrong PINs allowed before the code changes and pairing pauses.
    static let maxWrongPINAttempts = 5

    /// How long pairing pauses after too many wrong PINs.
    static let wrongPINLockout: TimeInterval = 30

    private let defaults: UserDefaults
    private let key = "EclipseTV.pairing.pairedDevices"
    /// v2 allowlist keyed by device name; dropped because names are no longer unique.
    private let legacyKey = "EclipseTV.pairing.pairedPhones"
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "PairedPeerStore")

    /// Current on-screen pairing PIN. Regenerated on demand; not persisted.
    var currentPIN: String {
        lock.lock()
        defer { lock.unlock() }
        return pin
    }
    private var pin: String

    private var wrongPINCount = 0
    private var lockedUntil: Date?
    /// Invitations and connections arrive on different Multipeer queues.
    private let lock = NSRecursiveLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.pin = PeerPairing.generatePIN()
        defaults.removeObject(forKey: legacyKey)
    }

    /// Whether the phone with `deviceKey` has completed a successful PIN pair on this TV.
    func isPaired(deviceKey: String) -> Bool {
        pairedDevices()[Self.hash(deviceKey)] != nil
    }

    /// Records a successful pair so future invites can use the remembered context.
    func remember(deviceKey: String, displayName: String) {
        lock.lock()
        defer { lock.unlock() }
        var devices = pairedDevices()
        devices[Self.hash(deviceKey)] = displayName
        persist(devices)
        logger.info("Paired phone remembered: \(displayName, privacy: .private)")
    }

    /// Clears every paired phone, so each must enter the on-screen code again.
    func forgetAll() {
        defaults.removeObject(forKey: key)
        logger.info("All paired phones forgotten")
    }

    /// Display names of paired phones for UI (may repeat, e.g. several "iPhone").
    func allPairedNames() -> [String] {
        pairedDevices().values.sorted()
    }

    /// Issues a new PIN and returns it. Call when the user asks to re-pair or after a
    /// successful pair if you want the old code to stop working.
    @discardableResult
    func rotatePIN() -> String {
        lock.lock()
        defer { lock.unlock() }
        pin = PeerPairing.generatePIN()
        wrongPINCount = 0
        logger.info("Pairing PIN rotated")
        return pin
    }

    /// Checks a PIN from an invitation, counting wrong guesses. After
    /// `maxWrongPINAttempts` wrong tries the code changes and every PIN is refused for
    /// `wrongPINLockout` seconds. Returns whether the PIN is accepted; `rotated` is true
    /// when this call changed the on-screen code.
    func checkPIN(_ candidate: String, now: Date = Date()) -> (accepted: Bool, rotated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let lockedUntil, now < lockedUntil { return (false, false) }
        lockedUntil = nil
        if candidate == pin {
            wrongPINCount = 0
            return (true, false)
        }
        wrongPINCount += 1
        guard wrongPINCount >= Self.maxWrongPINAttempts else { return (false, false) }
        lockedUntil = now.addingTimeInterval(Self.wrongPINLockout)
        rotatePIN()
        logger.info("Too many wrong pairing codes; code changed and pairing paused")
        return (false, true)
    }

    // MARK: - Private

    private static func hash(_ deviceKey: String) -> String {
        SHA256.hash(data: Data(deviceKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Paired phones: device-key hash → display name.
    private func pairedDevices() -> [String: String] {
        guard let data = defaults.data(forKey: key),
              let devices = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return devices
    }

    private func persist(_ devices: [String: String]) {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: key)
        }
    }
}
