//
//  QuestPollAccount.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Persists the QuestPoll host PIN (Keychain) and client `x-host-id`.
final class QuestPollAccount {
    static let shared = QuestPollAccount()

    private static let pinKey = "Eclipse.questpoll.hostPin"
    private static let hostIdKey = "Eclipse.questpoll.hostId"

    private let defaults: UserDefaults
    /// Injected for tests; production uses `KeychainStore`.
    private let keychainGet: (String) -> String?
    private let keychainSet: (String, String) -> Void
    private let keychainRemove: (String) -> Void

    /// - Parameters:
    ///   - defaults: Suite for `hostId` and legacy PIN migration.
    ///   - keychainGet: Read PIN (defaults to Keychain).
    ///   - keychainSet: Write PIN.
    ///   - keychainRemove: Delete PIN.
    init(
        defaults: UserDefaults = .standard,
        keychainGet: @escaping (String) -> String? = { KeychainStore.string(forKey: $0) },
        keychainSet: @escaping (String, String) -> Void = {
            KeychainStore.set($0, forKey: $1)
        },
        keychainRemove: @escaping (String) -> Void = {
            KeychainStore.removeValue(forKey: $0)
        }
    ) {
        self.defaults = defaults
        self.keychainGet = keychainGet
        self.keychainSet = keychainSet
        self.keychainRemove = keychainRemove
        migrateLegacyPINIfNeeded()
    }

    /// Whether a host PIN is stored (not yet verified against the network).
    var isLinked: Bool {
        hostPIN?.isEmpty == false
    }

    /// Host PIN for `x-host-pin`, or nil when unlinked.
    var hostPIN: String? {
        migrateLegacyPINIfNeeded()
        let pin = keychainGet(Self.pinKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pin, !pin.isEmpty else { return nil }
        return pin
    }

    /// Stable client id required by session create / control.
    var hostId: String {
        if let stored = defaults.string(forKey: Self.hostIdKey), !stored.isEmpty {
            return stored
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Self.hostIdKey)
        return generated
    }

    /// Saves a verified PIN in the Keychain.
    func link(pin: String) {
        keychainSet(pin, Self.pinKey)
        defaults.removeObject(forKey: Self.pinKey)
    }

    /// Drops the PIN; keeps `hostId` so a re-link can resume the same controller.
    func unlink() {
        keychainRemove(Self.pinKey)
        defaults.removeObject(forKey: Self.pinKey)
    }

    // MARK: - Private

    private func migrateLegacyPINIfNeeded() {
        guard let legacy = defaults.string(forKey: Self.pinKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        else { return }
        if keychainGet(Self.pinKey)?.isEmpty != false {
            keychainSet(legacy, Self.pinKey)
        }
        defaults.removeObject(forKey: Self.pinKey)
    }
}
